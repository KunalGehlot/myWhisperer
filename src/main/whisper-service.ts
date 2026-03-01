import OpenAI, { toFile } from 'openai';

interface TranscribeSettings {
  apiKey: string;
  model: string;
  language: string;
}

interface TranscribeResult {
  text: string;
  language: string;
  duration: number;
}

class WhisperService {
  async transcribe(
    audioBuffer: Buffer,
    settings: TranscribeSettings
  ): Promise<TranscribeResult> {
    const client = new OpenAI({ apiKey: settings.apiKey });

    const file = await toFile(audioBuffer, 'recording.webm', {
      type: 'audio/webm',
    });

    const startTime = Date.now();

    const params: OpenAI.Audio.TranscriptionCreateParams = {
      file,
      model: settings.model || 'whisper-1',
      response_format: 'verbose_json',
    };

    if (settings.language && settings.language !== 'auto') {
      params.language = settings.language;
    }

    const response = await client.audio.transcriptions.create(params);

    const elapsed = (Date.now() - startTime) / 1000;

    return {
      text: typeof response === 'string' ? response : (response as any).text,
      language:
        (response as any).language || settings.language || 'auto',
      duration: (response as any).duration || elapsed,
    };
  }
}

export { WhisperService };
