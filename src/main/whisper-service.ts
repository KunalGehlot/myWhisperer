/**
 * OpenAI Whisper transcription service for myWhisperer.
 * Handles audio-to-text conversion with client caching for efficiency.
 */
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

/** Manages Whisper API calls with a cached OpenAI client to avoid redundant instantiation. */
class WhisperService {
  private cachedClient: OpenAI | null = null;
  private cachedApiKey: string | null = null;

  /** Returns a cached OpenAI client, creating a new one only when the API key changes. */
  private getClient(apiKey: string): OpenAI {
    if (this.cachedClient && this.cachedApiKey === apiKey) {
      return this.cachedClient;
    }
    this.cachedClient = new OpenAI({ apiKey });
    this.cachedApiKey = apiKey;
    return this.cachedClient;
  }

  /** Transcribes an audio buffer using the Whisper API and returns text, language, and duration. */
  async transcribe(
    audioBuffer: Buffer,
    settings: TranscribeSettings
  ): Promise<TranscribeResult> {
    const client = this.getClient(settings.apiKey);

    const file = await toFile(audioBuffer, 'recording.webm', {
      type: 'audio/webm',
    });

    const startTime = Date.now();

    const params: OpenAI.Audio.TranscriptionCreateParams = {
      file,
      model: settings.model || 'whisper-1',
      response_format: 'verbose_json' as const,
    };

    if (settings.language && settings.language !== 'auto') {
      params.language = settings.language;
    }

    const response = await client.audio.transcriptions.create({
      ...params,
      response_format: 'verbose_json' as const,
    });

    const elapsed = (Date.now() - startTime) / 1000;
    const verbose = response as OpenAI.Audio.TranscriptionVerbose;

    return {
      text: verbose.text,
      language: verbose.language || settings.language || 'auto',
      duration: verbose.duration || elapsed,
    };
  }
}

export { WhisperService };
