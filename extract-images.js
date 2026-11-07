const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const questionsPath = path.join(__dirname, "questions.js");
const imagesDir = path.join(__dirname, "images");
const pattern = /data:image\/(png|jpe?g|gif|webp|svg\+xml);base64,[A-Za-z0-9+\/=]+/g;
const extensionByMime = {
  png: "png",
  jpg: "jpg",
  jpeg: "jpg",
  gif: "gif",
  webp: "webp",
  "svg+xml": "svg"
};
const original = fs.readFileSync(questionsPath, "utf8");
const originalSize = Buffer.byteLength(original, "utf8");
const uniqueImages = new Map();
let imageCount = 0;

fs.mkdirSync(imagesDir, { recursive: true });

const updated = original.replace(pattern, dataUri => {
  const separator = dataUri.indexOf(";base64,");
  const mime = dataUri.slice("data:image/".length, separator);
  const imageData = Buffer.from(dataUri.slice(separator + ";base64,".length), "base64");
  const digest = crypto.createHash("sha256").update(mime).update("\0").update(imageData).digest("hex");
  let relativePath = uniqueImages.get(digest);

  if (!relativePath) {
    const extension = extensionByMime[mime];
    if (!extension) throw new Error(`Unsupported image MIME type: ${mime}`);
    relativePath = `images/img_${uniqueImages.size + 1}.${extension}`;
    fs.writeFileSync(path.join(__dirname, relativePath), imageData);
    uniqueImages.set(digest, relativePath);
  }

  imageCount += 1;
  return relativePath;
});

if (imageCount === 0) throw new Error("No base64 data:image values found; questions.js was not changed.");

const tempPath = path.join(__dirname, "questions.tmp.js");
fs.writeFileSync(tempPath, updated, "utf8");
try {
  require("node:child_process").execFileSync(process.execPath, ["--check", tempPath], { stdio: "inherit" });
  fs.renameSync(tempPath, questionsPath);
} catch (error) {
  fs.rmSync(tempPath, { force: true });
  throw new Error(`Updated questions.js failed its syntax check; original file was kept. ${error.message}`);
}

const updatedSize = fs.statSync(questionsPath).size;
console.log(`Image references replaced: ${imageCount}`);
console.log(`Unique image files written: ${uniqueImages.size}`);
console.log(`questions.js size: ${originalSize} bytes -> ${updatedSize} bytes`);
