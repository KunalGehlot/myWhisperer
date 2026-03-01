const sharp = require('sharp');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const RESOURCES_DIR = path.join(__dirname, '..', 'resources');

// Professional microphone icon SVG with indigo/purple gradient
const svgIcon = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#4F46E5"/>
      <stop offset="100%" style="stop-color:#7C3AED"/>
    </linearGradient>
    <linearGradient id="mic" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" style="stop-color:#FFFFFF"/>
      <stop offset="100%" style="stop-color:#E0E7FF"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" rx="224" fill="url(#bg)"/>
  <!-- Microphone body -->
  <rect x="412" y="220" width="200" height="340" rx="100" fill="url(#mic)"/>
  <!-- Microphone arc -->
  <path d="M 312 460 Q 312 620 512 620 Q 712 620 712 460" fill="none" stroke="white" stroke-width="40" stroke-linecap="round"/>
  <!-- Stand -->
  <line x1="512" y1="620" x2="512" y2="740" stroke="white" stroke-width="40" stroke-linecap="round"/>
  <line x1="392" y1="740" x2="632" y2="740" stroke="white" stroke-width="40" stroke-linecap="round"/>
  <!-- Sound waves -->
  <path d="M 220 380 Q 180 512 220 644" fill="none" stroke="white" stroke-width="24" stroke-linecap="round" opacity="0.5"/>
  <path d="M 140 320 Q 80 512 140 704" fill="none" stroke="white" stroke-width="24" stroke-linecap="round" opacity="0.3"/>
  <path d="M 804 380 Q 844 512 804 644" fill="none" stroke="white" stroke-width="24" stroke-linecap="round" opacity="0.5"/>
  <path d="M 884 320 Q 944 512 884 704" fill="none" stroke="white" stroke-width="24" stroke-linecap="round" opacity="0.3"/>
</svg>`;

async function main() {
  fs.mkdirSync(RESOURCES_DIR, { recursive: true });

  // Generate 1024x1024 PNG
  const pngBuffer = await sharp(Buffer.from(svgIcon)).resize(1024, 1024).png().toBuffer();
  fs.writeFileSync(path.join(RESOURCES_DIR, 'icon.png'), pngBuffer);
  console.log('Created icon.png');

  // Generate macOS .icns using iconutil
  if (process.platform === 'darwin') {
    const iconsetDir = path.join(RESOURCES_DIR, 'icon.iconset');
    fs.mkdirSync(iconsetDir, { recursive: true });

    const sizes = [16, 32, 64, 128, 256, 512];
    for (const size of sizes) {
      await sharp(pngBuffer).resize(size, size).png().toFile(path.join(iconsetDir, `icon_${size}x${size}.png`));
      if (size <= 512) {
        await sharp(pngBuffer).resize(size * 2, size * 2).png().toFile(path.join(iconsetDir, `icon_${size}x${size}@2x.png`));
      }
    }

    execSync(`iconutil -c icns "${iconsetDir}" -o "${path.join(RESOURCES_DIR, 'icon.icns')}"`);
    fs.rmSync(iconsetDir, { recursive: true });
    console.log('Created icon.icns');
  }

  // Generate Windows .ico
  try {
    const pngToIco = require('png-to-ico');
    const pngPath = path.join(RESOURCES_DIR, 'icon.png');
    const icoBuffer = await pngToIco.default(pngPath);
    fs.writeFileSync(path.join(RESOURCES_DIR, 'icon.ico'), icoBuffer);
    console.log('Created icon.ico');
  } catch (err) {
    console.log('Could not create .ico:', err.message);
    fs.copyFileSync(path.join(RESOURCES_DIR, 'icon.png'), path.join(RESOURCES_DIR, 'icon.ico'));
    console.log('Copied icon.png as icon.ico fallback');
  }
}

main().catch(console.error);
