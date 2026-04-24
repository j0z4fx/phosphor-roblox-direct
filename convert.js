const fs = require("fs");
const path = require("path");
const sharp = require("sharp");

const INPUT_DIR = path.join(__dirname, "build", "phosphor", "assets");
const OUTPUT_DIR = path.join(__dirname, "build", "outputs", "formatted_icons");
const WEIGHTS = ["thin", "light", "regular", "bold", "fill", "duotone"];

function forceSvgWhite(svg) {
  return svg
    .replace(/fill="(?!none)[^"]*"/gi, 'fill="white"')
    .replace(/stroke="(?!none)[^"]*"/gi, 'stroke="white"')
    .replace(/<svg([^>]*)>/i, '<svg$1 fill="white" stroke="white">');
}

async function convertAll() {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });

  let total = 0;

  for (const weight of WEIGHTS) {
    const inputWeightDir = path.join(INPUT_DIR, weight);

    if (!fs.existsSync(inputWeightDir)) {
      console.warn(`Missing: ${inputWeightDir}`);
      continue;
    }

    const files = fs.readdirSync(inputWeightDir).filter(file => file.endsWith(".svg"));

    for (const file of files) {
      const inputPath = path.join(inputWeightDir, file);
      const outputName = `${weight}__${file.replace(".svg", ".png")}`;
      const outputPath = path.join(OUTPUT_DIR, outputName);

      const svg = forceSvgWhite(fs.readFileSync(inputPath, "utf8"));

      await sharp(Buffer.from(svg))
        .resize(48, 48, { fit: "contain" })
        .png()
        .toFile(outputPath);

      total++;
    }

    console.log(`Converted ${weight}: ${files.length}`);
  }

  console.log(`Done: ${total} icons`);
}

convertAll().catch(err => {
  console.error(err);
  process.exit(1);
});
