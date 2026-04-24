const fs = require('fs');
const path = require('path');
const sharp = require('sharp');

const INPUT_DIR = path.join(__dirname, 'build', 'phosphor', 'assets');
// Flat output matching tarmac.toml glob and main.luau's weight__icon.png convention
const OUTPUT_DIR = path.join(__dirname, 'build', 'outputs', 'formatted_icons');
const WEIGHTS = ['thin', 'light', 'regular', 'bold', 'fill', 'duotone'];

async function convertAll() {
    if (!fs.existsSync(OUTPUT_DIR)) {
        fs.mkdirSync(OUTPUT_DIR, { recursive: true });
    }

    let total = 0;

    for (const weight of WEIGHTS) {
        const inputWeightDir = path.join(INPUT_DIR, weight);

        if (!fs.existsSync(inputWeightDir)) {
            console.warn(`Weight folder not found, skipping: ${weight}`);
            continue;
        }

        const files = fs.readdirSync(inputWeightDir).filter(f => f.endsWith('.svg'));

        for (const file of files) {
            const inputPath = path.join(inputWeightDir, file);
            // Flat naming: weight__iconname.png (matches main.luau's parser)
            const outName = `${weight}__${file.replace('.svg', '.png')}`;
            const outputPath = path.join(OUTPUT_DIR, outName);

            await sharp(inputPath)
                .resize(48, 48)
                .png()
                .toFile(outputPath);

            total++;
            if (total % 500 === 0) {
                console.log(`Progress: ${total} files converted...`);
            }
        }
        console.log(`Done weight: ${weight} (${files.length} icons)`);
    }

    console.log(`\nAll done! Converted ${total} SVGs -> ${OUTPUT_DIR}`);
}

convertAll();
