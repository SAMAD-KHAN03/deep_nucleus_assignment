import http from "http";
import fs from "fs";
import path from "path";
import os from "os";
import { v4 as uuidv4 } from "uuid";
import multiparty from "multiparty";
import { spawn } from "child_process";
import AWS from "aws-sdk";

// Server config
const PORT = process.env.PORT || 3000;
const TMP_DIR = os.tmpdir();
const bucketName = "";

// Configure AWS SDK with hardcoded credentials (for testing ONLY)
const s3 = new AWS.S3({
  accessKeyId: "",
  secretAccessKey: "",
  region: "",
});

// Helper to convert Color (#RRGGBB) to FFmpeg compatible
function sanitizeColor(color) {
  if (!color) return "#FFFFFF";
  if (color.startsWith("#")) return color;
  return `#${color}`;
}

async function convertToMp4(inputPath) {
  const ext = path.extname(inputPath).toLowerCase();
  if (ext === ".mp4") {
    console.log("Video already mp4, skipping conversion");
    return inputPath;
  }

  const outputFileName = `converted_${uuidv4()}.mp4`;
  const outputPath = path.join(TMP_DIR, outputFileName);

  const ffmpegArgs = [
    "-y", // overwrite if exists
    "-i",
    inputPath, // input file
    "-c:v",
    "libx264", // video codec
    "-preset",
    "fast", // speed/quality tradeoff
    "-crf",
    "23", // quality
    "-c:a",
    "aac", // audio codec
    "-movflags",
    "+faststart", // optimize for streaming
    outputPath,
  ];

  console.log("Converting video to mp4 with args:", ffmpegArgs.join(" "));

  const ffmpeg = spawn("ffmpeg", ffmpegArgs);

  ffmpeg.stdout.on("data", (data) =>
    console.log("ffmpeg stdout:", data.toString())
  );
  ffmpeg.stderr.on("data", (data) =>
    console.log("ffmpeg stderr:", data.toString())
  );

  await new Promise((resolve, reject) => {
    ffmpeg.on("close", (code) => {
      console.log("FFmpeg conversion exited with code", code);
      if (code !== 0)
        return reject(new Error(`Video conversion failed with code ${code}`));
      resolve(true);
    });
  });

  return outputPath;
}
function buildDrawTextFilters(overlays, videoWidth, videoHeight) {
  return overlays
    .map((overlay) => {
      // Convert normalized coordinates to absolute pixels
      const x = Math.floor((overlay.x ?? 0) * videoWidth);
      const y = Math.floor((overlay.y ?? 0) * videoHeight);
      const fontsize = Math.floor((overlay.scale ?? 1) * 32);
      const fontcolor = sanitizeColor(overlay.color);

      // Escape special characters for FFmpeg
      const text = overlay.text
        .replace(/\\/g, "\\\\")
        .replace(/:/g, "\\:")
        .replace(/'/g, "'\\\\\\''");

      // Use borderw and bordercolor for proper text stroke
      return `drawtext=text='${text}':x=${x}:y=${y}:fontsize=${fontsize}:fontcolor=${fontcolor}:borderw=2:bordercolor=black`;
    })
    .join(",");
}

// Upload file to S3
function uploadToS3(filePath, key) {
  return new Promise((resolve, reject) => {
    const fileStream = fs.createReadStream(filePath);
    const params = { Bucket: bucketName, Key: key, Body: fileStream };
    s3.upload(params, (err, data) => {
      if (err) return reject(err);
      resolve(data.Location); // S3 URL
    });
  });
}
const server = http.createServer(async (req, res) => {
  console.log(
    `[${new Date().toISOString()}] Incoming request: ${req.method} ${req.url}`
  );

  if (req.method === "POST" && req.url === "/render-video") {
    const form = new multiparty.Form({ uploadDir: TMP_DIR });

    form.parse(req, async (err, fields, files) => {
      console.log(`[${new Date().toISOString()}] Form parsing complete`);
      console.log("Fields received:", fields);
      console.log("Files received:", files);

      if (err) {
        console.error("Form parse error:", err);
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: err.message }));
        return;
      }

      if (!files.video || files.video.length === 0) {
        console.warn("No video file uploaded");
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "No video file uploaded" }));
        return;
      }

      if (!fields.metadata || fields.metadata.length === 0) {
        console.warn("No metadata provided");
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "No metadata provided" }));
        return;
      }

      let metadata;
      try {
        console.log("Raw metadata string:", fields.metadata[0]);
        metadata = JSON.parse(fields.metadata[0]);
        console.log("Parsed metadata:", metadata);
      } catch (parseErr) {
        console.error("Metadata parse error:", parseErr);
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Invalid metadata JSON" }));
        return;
      }

      const videoFile = files.video[0];
      const originalPath = videoFile.path;
      let inputPath = originalPath;
      const outputFileName = `output_${uuidv4()}.mp4`;
      const outputPath = path.join(TMP_DIR, outputFileName);

      try {
        inputPath = await convertToMp4(originalPath);
        console.log("Running ffprobe on", inputPath);
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
        ffprobe.stdout.on("data", (data) => (probeOutput += data.toString()));
        ffprobe.stderr.on("data", (data) =>
          console.error("ffprobe stderr:", data.toString())
        );

        await new Promise((resolve, reject) => {
          ffprobe.on("close", (code) => {
            if (code !== 0) return reject(new Error("ffprobe failed"));
            resolve(true);
          });
        });

        console.log("ffprobe output:", probeOutput);
        const [videoWidth, videoHeight] = probeOutput
          .trim()
          .split(",")
          .map(Number);
        console.log(`Video resolution: ${videoWidth}x${videoHeight}`);

        const filter = buildDrawTextFilters(metadata, videoWidth, videoHeight);
        console.log("FFmpeg filter:", filter);

        const ffmpeg = spawn("ffmpeg", [
          "-i",
          inputPath,
          "-vf",
          filter,
          "-c:a",
          "copy",
          outputPath,
        ]);
        ffmpeg.stderr.on("data", (data) =>
          console.log("ffmpeg:", data.toString())
        );

        await new Promise((resolve, reject) => {
          ffmpeg.on("close", (code) => {
            if (code !== 0)
              return reject(new Error(`FFmpeg exited with code ${code}`));
            resolve(true);
          });
        });

        console.log("FFmpeg finished, uploading to S3...");
        const userid = metadata[0]?.userid || "default_user";
        const s3Key = `${userid}/${outputFileName}`;

        const s3Url = await uploadToS3(outputPath, s3Key);
        console.log("Upload successful:", s3Url);

        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ s3_url: s3Url }));

        console.log("Cleaning up temp files...");
        fs.unlink(inputPath, () => console.log("Deleted input file"));
        fs.unlink(outputPath, () => console.log("Deleted output file"));
      } catch (processErr) {
        console.error("Processing error:", processErr);
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: processErr.message }));
      }
    });

    return;
  }

  console.warn("Endpoint not found");
  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "Not found" }));
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Server listening on port ${PORT}`);
});
