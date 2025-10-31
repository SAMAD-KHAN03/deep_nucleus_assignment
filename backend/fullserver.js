import http from "http";
import fs from "fs";
import fsp from "fs/promises";
import path from "path";
import os from "os";
import { v4 as uuidv4 } from "uuid";
import https from "https";
import { spawn } from "child_process";
import AWS from "aws-sdk";
import multiparty from "multiparty";
import url from "url";

// ---------- CONFIG ----------
const PORT = process.env.PORT || 3000;
const TMP_DIR = os.tmpdir();
const S3_BUCKET = "";

if (!S3_BUCKET) {
  console.error("Please set S3_BUCKET variable");
  process.exit(1);
}

AWS.config.update({
  accessKeyId: "",
  secretAccessKey: "",
  region: "",
});

const s3 = new AWS.S3();
const transcribe = new AWS.TranscribeService();

// ---------- HELPERS ----------
async function convertToMp4(inputPath) {
  const ext = path.extname(inputPath).toLowerCase();
  if (ext === ".mp4") return inputPath;

  const outputPath = path.join(TMP_DIR, `converted_${uuidv4()}.mp4`);
  const ffmpegArgs = [
    "-y",
    "-i",
    inputPath,
    "-c:v",
    "libx264",
    "-preset",
    "fast",
    "-crf",
    "23",
    "-c:a",
    "aac",
    "-movflags",
    "+faststart",
    outputPath,
  ];

  await new Promise((resolve, reject) => {
    const ffmpeg = spawn("ffmpeg", ffmpegArgs);
    ffmpeg.stderr.on("data", (d) => console.log("ffmpeg:", d.toString()));
    ffmpeg.on("close", (code) =>
      code === 0 ? resolve() : reject(new Error(`FFmpeg failed: ${code}`))
    );
  });

  return outputPath;
}

function buildDrawTextFilters(overlays, videoWidth, videoHeight) {
  if (!Array.isArray(overlays) || overlays.length === 0) {
    console.log("No text overlays to process");
    return null; // Return null instead of empty string
  }

  return overlays
    .map((overlay) => {
      const x = Math.floor((overlay.x ?? 0) * videoWidth);
      const y = Math.floor((overlay.y ?? 0) * videoHeight);
      const fontsize = Math.floor((overlay.scale ?? 1) * 32);
      const fontcolor = overlay.color || "#FFFFFF";
      const text = overlay.text
        .replace(/\\/g, "\\\\")
        .replace(/:/g, "\\:")
        .replace(/'/g, "'\\\\\\''");

      return `drawtext=text='${text}':x=${x}:y=${y}:fontsize=${fontsize}:fontcolor=${fontcolor}:borderw=2:bordercolor=black`;
    })
    .join(",");
}

function uploadToS3(localPath, key) {
  const stream = fs.createReadStream(localPath);
  return s3.upload({ Bucket: S3_BUCKET, Key: key, Body: stream }).promise();
}

function startTranscribeJob(jobName, mediaUri, outputKeyPrefix) {
  const params = {
    TranscriptionJobName: jobName,
    LanguageCode: "en-US",
    MediaFormat: "mp4",
    Media: { MediaFileUri: mediaUri },
    OutputBucketName: S3_BUCKET,
    OutputKey: `${outputKeyPrefix}/`,
    Subtitles: { Formats: ["vtt", "srt"] },
  };
  return transcribe.startTranscriptionJob(params).promise();
}

function getTranscriptionJob(jobName) {
  return transcribe
    .getTranscriptionJob({ TranscriptionJobName: jobName })
    .promise();
}

function fetchJsonFromUrl(url) {
  return new Promise((resolve, reject) => {
    https
      .get(url, (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          try {
            resolve(JSON.parse(data));
          } catch (e) {
            reject(e);
          }
        });
      })
      .on("error", reject);
  });
}

// ---------- SERVER ----------
const server = http.createServer(async (req, res) => {
  try {
    const parsedUrl = new URL(req.url, `http://${req.headers.host}`);
    const pathname = parsedUrl.pathname;

    // ========== PROCESS VIDEO ==========
    if (req.method === "POST" && pathname === "/process-video") {
      const form = new multiparty.Form({
        uploadDir: TMP_DIR,
        maxFilesSize: 1024 * 1024 * 1024, // 1GB
        maxFieldsSize: 10 * 1024 * 1024, // 10MB for metadata
        maxFields: 20,
      });

      form.parse(req, async (err, fields, files) => {
        if (err) {
          console.error("Form parse error:", err);
          return res
            .writeHead(500, { "Content-Type": "application/json" })
            .end(JSON.stringify({ error: err.message }));
        }

        // Validate inputs
        const userId = fields.userId?.[0];
        const videoId = fields.videoId?.[0];
        const videoHash = fields.videoHash?.[0];
        const metadataStr = fields.metadata?.[0];
        const videoFile = files.video?.[0];

        if (!userId || !videoId || !videoHash || !metadataStr || !videoFile) {
          return res.writeHead(400, { "Content-Type": "application/json" }).end(
            JSON.stringify({
              error:
                "Missing one of: userId, videoId, videoHash, metadata, video",
            })
          );
        }

        let metadata;
        try {
          metadata = JSON.parse(metadataStr);
        } catch (parseErr) {
          console.error("Metadata parse error:", parseErr);
          return res
            .writeHead(400, { "Content-Type": "application/json" })
            .end(JSON.stringify({ error: "Invalid metadata JSON" }));
        }

        if (!Array.isArray(metadata)) {
          console.error("Expected metadata to be an array, got:", metadata);
          return res
            .writeHead(400, { "Content-Type": "application/json" })
            .end(JSON.stringify({ error: "Metadata must be an array" }));
        }

        console.log("📦 Processing video:");
        console.log("  userId:", userId);
        console.log("  videoHash:", videoHash);
        console.log("  Text overlays:", metadata.length);

        try {
          // Convert and get video info
          const inputPath = await convertToMp4(videoFile.path);

          // Get resolution
          const ffprobe = spawn("ffprobe", [
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-of",
            "csv=p=0",
            inputPath,
          ]);

          let probeOutput = "";
          ffprobe.stdout.on("data", (d) => (probeOutput += d.toString()));
          await new Promise((r, rej) =>
            ffprobe.on("close", (c) => (c === 0 ? r() : rej()))
          );

          const [w, h] = probeOutput.trim().split(",").map(Number);
          console.log(`  Video resolution: ${w}x${h}`);

          // Build text overlay filter
          const filter = buildDrawTextFilters(metadata, w, h);

          let outputPath;

          // If no text overlays, just copy the converted video
          if (!filter) {
            console.log("  No text overlays, using original video");
            outputPath = inputPath;
          } else {
            // Burn text overlay
            outputPath = path.join(TMP_DIR, `${uuidv4()}_processed.mp4`);
            console.log("  Burning text overlays...");

            const ffmpeg = spawn("ffmpeg", [
              "-y",
              "-i",
              inputPath,
              "-vf",
              filter,
              "-c:a",
              "copy",
              outputPath,
            ]);

            ffmpeg.stderr.on("data", (d) =>
              console.log("ffmpeg:", d.toString())
            );

            await new Promise((r, rej) =>
              ffmpeg.on("close", (c) => {
                if (c === 0) {
                  r();
                } else {
                  rej(new Error(`FFmpeg failed with code ${c}`));
                }
              })
            );
          }

          // ✅ Upload to S3 path: userId/videoHash/videoHash.mp4
          const videoS3Key = `${userId}/${videoHash}/${videoHash}.mp4`;
          const metadataS3Key = `${userId}/${videoHash}/${videoHash}.json`;

          console.log("☁️  Uploading to S3:");
          console.log("  Video key:", videoS3Key);
          console.log("  Metadata key:", metadataS3Key);

          // Upload video
          const { Location: s3Url } = await uploadToS3(outputPath, videoS3Key);
          console.log("✅ Video uploaded:", s3Url);

          // Upload metadata JSON
          await s3
            .upload({
              Bucket: S3_BUCKET,
              Key: metadataS3Key,
              Body: metadataStr,
              ContentType: "application/json",
            })
            .promise();
          console.log("✅ Metadata uploaded");

          // Start Transcribe job → output in same folder
          const outputPrefix = `${userId}/${videoHash}`;
          const jobName = `transcribe-${userId}-${videoHash}-${Date.now()}`;
          await startTranscribeJob(jobName, s3Url, outputPrefix);
          console.log("✅ Transcribe job started:", jobName);

          // Cleanup
          if (inputPath !== outputPath) {
            fs.unlink(inputPath, () => {});
          }
          if (outputPath !== inputPath) {
            fs.unlink(outputPath, () => {});
          }
          fs.unlink(videoFile.path, () => {});

          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(
            JSON.stringify({
              message: "Video processed and uploaded successfully",
              s3Url,
              videoHash,
              jobName,
            })
          );
        } catch (processingError) {
          console.error("🚨 Processing error:", processingError);
          res.writeHead(500, { "Content-Type": "application/json" });
          res.end(
            JSON.stringify({
              error: "Video processing failed",
              details: processingError.message,
            })
          );
        }
      });
      return;
    }

    // ========== LIST VIDEOS ==========
    if (req.method === "GET" && pathname === "/list-videos") {
      const userId = parsedUrl.searchParams.get("userId");

      if (!userId) {
        res.writeHead(400, { "Content-Type": "application/json" });
        return res.end(JSON.stringify({ error: "Missing userId parameter" }));
      }

      const Prefix = `${userId}/`;
      const response = await s3
        .listObjectsV2({ Bucket: S3_BUCKET, Prefix })
        .promise();

      console.log(
        `📋 Found ${response.Contents?.length || 0} objects for user ${userId}`
      );

      // Group by video hash folder
      const videosMap = {};
      response.Contents?.forEach((item) => {
        const parts = item.Key.split("/");
        if (parts.length >= 2) {
          const hash = parts[1];
          videosMap[hash] = videosMap[hash] || [];
          videosMap[hash].push(item.Key);
        }
      });

      // Generate signed URLs
      const results = await Promise.all(
        Object.keys(videosMap).map(async (hash) => {
          const videoKey = `${userId}/${hash}/${hash}.mp4`;
          const jsonKey = `${userId}/${hash}/${hash}.json`;

          const [videoUrl, subtitleUrl] = await Promise.all([
            s3.getSignedUrlPromise("getObject", {
              Bucket: S3_BUCKET,
              Key: videoKey,
              Expires: 3600,
            }),
            s3.getSignedUrlPromise("getObject", {
              Bucket: S3_BUCKET,
              Key: jsonKey,
              Expires: 3600,
            }),
          ]);

          return { hash, videoUrl, subtitleUrl };
        })
      );

      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ videos: results }));
      return;
    }

    // ========== CHECK TRANSCRIBE STATUS ==========
    if (req.method === "GET" && pathname === "/check-status") {
      const jobName = parsedUrl.searchParams.get("jobName");
      if (!jobName)
        return res
          .writeHead(400, { "Content-Type": "application/json" })
          .end(JSON.stringify({ error: "Missing jobName" }));

      const data = await getTranscriptionJob(jobName);
      const job = data.TranscriptionJob;

      if (
        job?.TranscriptionJobStatus === "COMPLETED" &&
        job.Transcript?.TranscriptFileUri
      ) {
        const transcript = await fetchJsonFromUrl(
          job.Transcript.TranscriptFileUri
        );
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ job, transcript }));
      } else {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ job }));
      }
      return;
    }

    // ========== DEBUG ENDPOINT ==========
    if (req.method === "GET" && pathname === "/debug-s3") {
      const userId = parsedUrl.searchParams.get("userId");

      const response = await s3
        .listObjectsV2({
          Bucket: S3_BUCKET,
          Prefix: userId ? `${userId}/` : "",
        })
        .promise();

      console.log(
        `📋 S3 Debug - Found ${response.Contents?.length || 0} objects:`
      );
      response.Contents?.forEach((item) => {
        console.log(`  - ${item.Key} (${item.Size} bytes)`);
      });

      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(
        JSON.stringify({
          bucket: S3_BUCKET,
          prefix: userId ? `${userId}/` : "",
          count: response.Contents?.length || 0,
          objects:
            response.Contents?.map((item) => ({
              key: item.Key,
              size: item.Size,
              lastModified: item.LastModified,
            })) || [],
        })
      );
      return;
    }

    // ========== DEFAULT ==========
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end(
      `Video Processor + Transcriber
POST /process-video (userId, videoId, videoHash, metadata, video)
GET /list-videos?userId=...
GET /check-status?jobName=...
GET /debug-s3?userId=... (debug endpoint)`
    );
  } catch (err) {
    console.error("Server error:", err);
    res.writeHead(500, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: err.message }));
  }
});

server.listen(PORT, "0.0.0.0", () =>
  console.log(`✅ Server running on port ${PORT}`)
);
