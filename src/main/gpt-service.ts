/**
 * GPT text formatting service for myWhisperer.
 * Post-processes raw Whisper transcriptions with context-aware, level-based formatting.
 */
import OpenAI from 'openai';
import type { AppContext } from './context-detector';

interface FormatSettings {
  apiKey: string;
  model: string;
  personalDictionary: string[];
  formatPrompt: string;
  formattingLevel: number;
  appContext?: AppContext;
}

const CONTEXT_AWARE_PROMPT = `You are an intelligent voice-to-text assistant integrated into a desktop application.
You receive two inputs: (1) raw speech transcription and (2) context about where the user is currently typing (application name and window title).

Your job is to format the transcription appropriately based on the context:

**Context-Aware Formatting Rules:**

- **Email clients** (Mail, Outlook, Gmail, Thunderbird, Spark, Airmail, etc.):
  Format as a professional email. Add appropriate greeting and sign-off if the content implies a new email and they are missing. Use proper email paragraph structure. Keep tone professional but warm. For replies, skip the greeting if the content is brief.

- **Chat/messaging apps** (Slack, Discord, Teams, WhatsApp, Telegram, iMessage, Messages, Signal, etc.):
  Keep it casual and conversational. Short sentences. No formal structure needed. Preserve the speaker's natural tone. Light punctuation only. Do not add greetings or sign-offs.

- **Note-taking apps** (Notion, Obsidian, Apple Notes, OneNote, Bear, Evernote, Craft, Joplin, etc.):
  Format as clean, organized notes. Use bullet points for lists. Add markdown headers if the content covers multiple distinct topics. Be concise and scannable.

- **Document editors** (Word, Google Docs, Pages, LibreOffice Writer, TextEdit, Scrivener, etc.):
  Format as polished prose. Full sentences, proper paragraphs. Professional writing style with clear structure and logical flow.

- **Code editors/IDEs** (VS Code, Visual Studio Code, IntelliJ, WebStorm, PyCharm, Xcode, Vim, Neovim, Sublime Text, Cursor, Zed, Atom, etc.):
  Format as code comments (// for JS/TS/Java/C, # for Python/Ruby/Shell, depending on file type if discernible from the window title). If the speech clearly describes code logic or instructions to write code, attempt to output the actual code rather than a comment. Keep it precise and technical.

- **Spreadsheet apps** (Excel, Google Sheets, Numbers, LibreOffice Calc):
  Format as comma-separated or tab-separated values if the content sounds like data entries or a list of values. Otherwise, format as concise cell-appropriate text.

- **Presentation apps** (PowerPoint, Keynote, Google Slides, LibreOffice Impress):
  Format as concise bullet points suitable for slides. Short phrases, not full sentences. Focus on key points and impact.

- **Terminal/CLI** (Terminal, iTerm, iTerm2, Command Prompt, PowerShell, Warp, Alacritty, Kitty, Hyper, etc.):
  If the speech describes a command, output the actual shell command. If it describes multiple steps, output them as separate commands. Otherwise, format as a brief, technical comment prefixed with #.

- **Social media** (Twitter, X, LinkedIn, Facebook, Reddit, Instagram, Threads, Mastodon, etc.):
  Match the platform's tone and conventions. Keep within typical character limits. Casual but clear. Use hashtags if appropriate for the platform (Twitter/X, LinkedIn, Instagram).

- **Search bars / Browsers** (Chrome, Safari, Firefox, Arc, Edge, Brave, Opera, etc.):
  Format as a search query — concise keywords, no full sentences, no punctuation. Optimize for search engine understanding.

- **Task/project management** (Jira, Linear, Asana, Trello, Monday, Todoist, Things, TickTick, etc.):
  Format as a clear, actionable task description or comment. Use concise language. Include relevant context but stay focused.

- **Unknown/Other applications**:
  Default to clean, professional prose. Fix grammar, punctuation, capitalization. Remove filler words. Maintain the speaker's original meaning and tone.

**General Rules (always apply):**
- Remove filler words (um, uh, like, you know, so basically, I mean, sort of, kind of, right, etc.)
- Fix grammar, spelling, and punctuation
- If custom terminology/dictionary is provided, use those exact spellings
- Preserve the speaker's original meaning, intent, and key information
- Output ONLY the formatted text — no explanations, labels, preambles, or metadata`;

const LIGHT_PROMPT = `You are a minimal text editor. Take the raw speech transcription and make only essential corrections:
- Fix capitalization at the beginning of sentences
- Remove filler words (um, uh, like, you know, so basically, etc.)
- Fix obvious typos and misspellings
- Add basic punctuation (periods at sentence ends, commas for natural pauses)
Do NOT restructure sentences, change word choices, or rewrite anything. Preserve the speaker's exact phrasing and sentence structure.
If custom terminology is provided, use those exact spellings.
Output ONLY the corrected text with no explanations.`;

const MODERATE_PROMPT = `You are a text editor. Take the raw speech transcription and clean it up:
- Fix grammar, punctuation, and capitalization
- Remove filler words (um, uh, like, you know, so basically, etc.)
- Fix spelling errors and typos
- Lightly improve sentence flow where needed, but keep the speaker's original sentence structure and word choices where possible
- Do not heavily rewrite, restructure paragraphs, or change the tone
If custom terminology is provided, use those exact spellings.
Output ONLY the formatted text with no explanations.`;

/** Manages GPT API calls for text formatting with a cached OpenAI client. */
class GPTService {
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

  /** Returns the appropriate system prompt based on formatting level. */
  private getSystemPrompt(level: number, customPrompt: string): string {
    // Custom prompt always takes precedence
    if (customPrompt) return customPrompt;

    if (level <= 30) return LIGHT_PROMPT;
    if (level <= 70) return MODERATE_PROMPT;
    return CONTEXT_AWARE_PROMPT;
  }

  /** Builds the user message, injecting app context for high formatting levels. */
  private buildUserMessage(
    rawText: string,
    level: number,
    customPrompt: string,
    appContext?: AppContext
  ): string {
    // Only inject context for high-level formatting with the context-aware prompt
    if (level > 70 && !customPrompt && appContext && (appContext.appName || appContext.windowTitle)) {
      const contextLine = [
        appContext.appName && `Application: ${appContext.appName}`,
        appContext.windowTitle && `Window: ${appContext.windowTitle}`,
      ]
        .filter(Boolean)
        .join(' | ');

      return `[Context: ${contextLine}]\n\n${rawText}`;
    }
    return rawText;
  }

  /** Formats raw transcription text using GPT, with context-aware level-based prompts. */
  async formatText(rawText: string, settings: FormatSettings): Promise<string> {
    // Level 0 means no formatting — skip the GPT call entirely
    if (settings.formattingLevel === 0) {
      return rawText;
    }

    const client = this.getClient(settings.apiKey);

    let systemPrompt = this.getSystemPrompt(
      settings.formattingLevel,
      settings.formatPrompt
    );

    if (settings.personalDictionary && settings.personalDictionary.length > 0) {
      systemPrompt +=
        '\n\nCustom terminology/dictionary (use these exact spellings): ' +
        settings.personalDictionary.join(', ');
    }

    const userMessage = this.buildUserMessage(
      rawText,
      settings.formattingLevel,
      settings.formatPrompt,
      settings.appContext
    );

    // Scale temperature slightly with formatting level: 0.1 (light) to 0.3 (full)
    const temperature = Math.max(0.1, (settings.formattingLevel / 100) * 0.3);

    const response = await client.chat.completions.create({
      model: settings.model || 'gpt-4',
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userMessage },
      ],
      temperature,
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error('No response received from GPT');
    }

    return content.trim();
  }
}

export { GPTService };
