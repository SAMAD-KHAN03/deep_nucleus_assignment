import http from "http";
import fs from "fs";
import fsp from "fs/promises";
import path from "path";
import os from "os";
import { v4 as uuidv4 } from "uuid";
import AWS from "aws-sdk";
import https from "https";
import multiparty from "multiparty";

// ---------- CONFIG (via ENV) ----------
const REGION = process.env.AWS_REGION || "";
const S3_BUCKET = "";
const PORT = process.env.PORT || 3000;

if (!S3_BUCKET) {
  console.error("Please set S3_BUCKET environment variable.");
  process.exit(1);
}

AWS.config.update({
  accessKeyId: "",
  secretAccessKey: "",
  region: "",
});

const s3 = new AWS.S3({
  accessKeyId: "",
  secretAccessKey: "",
  region: "",
});
const transcribe = new AWS.TranscribeService();

// ---------- Helpers ----------
async function uploadFileToS3(localPath, key) {
  const stream = fs.createReadStream(localPath);
  const params = {
    Bucket: S3_BUCKET,
    Key: key,
    Body: stream,
  };
  return s3.upload(params).promise();
}
function startTranscribeJob(
  jobName,
  mediaUri,
  mediaFormat = "mp4",
  languageCode = "en-US"
) {
  const params = {
    TranscriptionJobName: jobName,
    LanguageCode: languageCode,
    MediaFormat: mediaFormat,
    Media: { MediaFileUri: mediaUri },
    OutputBucketName: S3_BUCKET,
    Subtitles: { Formats: ["vtt", "srt"] },
    // Remove Settings entirely if you don’t need speaker labeling or alternatives
    // Settings: {}
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
      .on("error", (err) => reject(err));
  });
}

// ---------- HTTP SERVER ----------
const server = http.createServer(async (req, res) => {
  try {
    if (req.method === "POST" && req.url === "/transcribe-video") {
      const form = new multiparty.Form();
      let tmpFilePath = null;
      let originalFilename = null;

      form.parse(req, async (err, fields, files) => {
        if (err) {
          res.writeHead(500, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: err.message }));
          return;
        }

        if (!files.file || files.file.length === 0) {
          res.writeHead(400, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ error: "No file uploaded" }));
          return;
        }

        const uploadedFile = files.file[0]; // input field name = "file"
        tmpFilePath = uploadedFile.path;
        originalFilename =
          uploadedFile.originalFilename || `video_${Date.now()}.mp4`;

        try {
          // Upload to S3
          const s3Key = `uploads/${uuidv4()}_${path.basename(
            originalFilename
          )}`;
          await uploadFileToS3(tmpFilePath, s3Key);

          // Remove local temp file
          await fsp.unlink(tmpFilePath).catch(() => {});

          const mediaUri = `s3://${S3_BUCKET}/${s3Key}`;
          const jobName = `transcribe-${Date.now()}-${uuidv4()}`;

          // Start Transcribe job
          await startTranscribeJob(
            jobName,
            mediaUri,
            path.extname(originalFilename).substring(1) || "mp4"
          );

          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ jobName, s3Uri: mediaUri }));
        } catch (err) {
          console.error("Upload/Transcribe error:", err);
          res.writeHead(500, { "Content-Type": "application/json" });
          res.end(
            JSON.stringify({ error: "Server error", details: err.message })
          );
        }
      });

      return;
    }

    // Check status endpoint: GET /check-status?jobName=...
    if (req.method === "GET" && req.url.startsWith("/check-status")) {
      const urlObj = new URL(req.url, `http://${req.headers.host}`);
      const jobName = urlObj.searchParams.get("jobName");
      if (!jobName) {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Missing jobName query parameter" }));
        return;
      }

      try {
        const data = await getTranscriptionJob(jobName);
        const job = data.TranscriptionJob;

        if (
          job &&
          job.TranscriptionJobStatus === "COMPLETED" &&
          job.Transcript &&
          job.Transcript.TranscriptFileUri
        ) {
          const transcriptJson = await fetchJsonFromUrl(
            job.Transcript.TranscriptFileUri
          );
          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ job, transcriptJson }));
          return;
        } else {
          res.writeHead(200, { "Content-Type": "application/json" });
          res.end(JSON.stringify({ job }));
          return;
        }
      } catch (err) {
        console.error("Check status error:", err);
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: err.message }));
        return;
      }
    }

    // Root endpoint
    if (req.method === "GET" && req.url === "/") {
      res.writeHead(200, { "Content-Type": "text/plain" });
      res.end(
        "Transcribe API (no-express) running\nPOST /upload-video (multipart/form-data file field: file)\nGET /check-status?jobName=<jobName>"
      );
      return;
    }

    res.writeHead(404, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "Not found" }));
  } catch (outerErr) {
    console.error("Server error:", outerErr);
    res.writeHead(500, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: outerErr.message }));
  }
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`Server listening on port ${PORT}`);
});
