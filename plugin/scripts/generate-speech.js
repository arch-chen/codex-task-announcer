'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { EdgeTTS } = require(path.join(__dirname, '..', 'vendor', 'node_modules', 'node-edge-tts'));

async function main() {
  const requestPath = process.argv[2];
  const outputPath = process.argv[3];
  if (!requestPath || !outputPath) {
    throw new Error('Usage: generate-speech.js <request.json> <output.mp3>');
  }

  const request = JSON.parse(fs.readFileSync(requestPath, 'utf8').replace(/^\uFEFF/, ''));
  if (typeof request.text !== 'string' || !request.text.trim()) {
    throw new Error('Speech text must be a non-empty string.');
  }
  if (typeof request.voice !== 'string' || !request.voice.trim()) {
    throw new Error('Voice must be a non-empty string.');
  }

  const tts = new EdgeTTS({
    voice: request.voice,
    lang: request.language || 'zh-CN',
    outputFormat: request.outputFormat || 'audio-24khz-48kbitrate-mono-mp3',
    rate: request.rate || 'default',
    pitch: request.pitch || 'default',
    volume: request.volume || 'default',
    timeout: Number(request.timeoutMs) || 20000,
  });

  try {
    await tts.ttsPromise(request.text, outputPath);
  } catch (error) {
    try {
      fs.rmSync(outputPath, { force: true });
    } catch {
    }
    throw error;
  }
}

main().catch((error) => {
  const message = error instanceof Error ? error.stack || error.message : String(error);
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});
