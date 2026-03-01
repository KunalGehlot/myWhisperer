import OpenAI from 'openai';

interface FormatSettings {
  apiKey: string;
  model: string;
  personalDictionary: string[];
  formatPrompt: string;
}

const DEFAULT_SYSTEM_PROMPT =
  'You are a professional text editor. Take the following raw speech transcription and transform it into clean, polished writing. Fix grammar, punctuation, capitalization, and remove filler words (um, uh, like, you know, etc). Maintain the speaker\'s original meaning and tone. If custom terminology is provided, use those exact spellings. Output ONLY the formatted text with no explanations.';

class GPTService {
  async formatText(
    rawText: string,
    settings: FormatSettings
  ): Promise<string> {
    const client = new OpenAI({ apiKey: settings.apiKey });

    let systemPrompt = settings.formatPrompt || DEFAULT_SYSTEM_PROMPT;

    if (settings.personalDictionary && settings.personalDictionary.length > 0) {
      systemPrompt +=
        '\n\nCustom terminology/dictionary (use these exact spellings): ' +
        settings.personalDictionary.join(', ');
    }

    const response = await client.chat.completions.create({
      model: settings.model || 'gpt-4',
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: rawText },
      ],
      temperature: 0.3,
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error('No response received from GPT');
    }

    return content.trim();
  }
}

export { GPTService };
