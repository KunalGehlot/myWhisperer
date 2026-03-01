// @vitest-environment node
import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock the openai module before importing GPTService
const mockCreate = vi.fn();
vi.mock('openai', () => {
  class MockOpenAI {
    chat = {
      completions: {
        create: mockCreate,
      },
    };
  }
  return { default: MockOpenAI };
});

import { GPTService } from './gpt-service';

function makeSettings(overrides: Record<string, unknown> = {}) {
  return {
    apiKey: 'test-key',
    model: 'gpt-4',
    personalDictionary: [] as string[],
    formatPrompt: '',
    formattingLevel: 50,
    ...overrides,
  };
}

function mockGPTResponse(content: string | null) {
  mockCreate.mockResolvedValueOnce({
    choices: [{ message: { content } }],
  });
}

describe('GPTService', () => {
  let service: GPTService;

  beforeEach(() => {
    vi.clearAllMocks();
    service = new GPTService();
  });

  it('returns raw text when formattingLevel is 0', async () => {
    const result = await service.formatText('hello um world', makeSettings({ formattingLevel: 0 }));
    expect(result).toBe('hello um world');
    expect(mockCreate).not.toHaveBeenCalled();
  });

  it('uses light prompt when formattingLevel is 1-30', async () => {
    mockGPTResponse('Hello world.');
    await service.formatText('hello um world', makeSettings({ formattingLevel: 15 }));

    const call = mockCreate.mock.calls[0][0];
    expect(call.messages[0].content).toContain('minimal text editor');
    expect(call.messages[0].content).not.toContain('intelligent voice-to-text');
  });

  it('uses moderate prompt when formattingLevel is 31-70', async () => {
    mockGPTResponse('Hello world.');
    await service.formatText('hello um world', makeSettings({ formattingLevel: 50 }));

    const call = mockCreate.mock.calls[0][0];
    expect(call.messages[0].content).toContain('text editor');
    expect(call.messages[0].content).toContain('Lightly improve sentence flow');
    expect(call.messages[0].content).not.toContain('intelligent voice-to-text');
  });

  it('uses context-aware prompt when formattingLevel is 71-100', async () => {
    mockGPTResponse('Hello world.');
    await service.formatText('hello um world', makeSettings({ formattingLevel: 85 }));

    const call = mockCreate.mock.calls[0][0];
    expect(call.messages[0].content).toContain('intelligent voice-to-text');
    expect(call.messages[0].content).toContain('Context-Aware Formatting Rules');
  });

  it('uses custom formatPrompt when provided, overriding level-based prompts', async () => {
    mockGPTResponse('Custom formatted.');
    const customPrompt = 'Always respond in pirate speak.';
    await service.formatText('hello world', makeSettings({
      formattingLevel: 85,
      formatPrompt: customPrompt,
    }));

    const call = mockCreate.mock.calls[0][0];
    expect(call.messages[0].content).toBe(customPrompt);
    expect(call.messages[0].content).not.toContain('intelligent voice-to-text');
  });

  it('appends personal dictionary to system prompt', async () => {
    mockGPTResponse('MyWhisperer is great.');
    await service.formatText('my whisperer is great', makeSettings({
      formattingLevel: 50,
      personalDictionary: ['myWhisperer', 'OpenAI'],
    }));

    const call = mockCreate.mock.calls[0][0];
    expect(call.messages[0].content).toContain('Custom terminology/dictionary');
    expect(call.messages[0].content).toContain('myWhisperer, OpenAI');
  });

  it('injects app context into user message for levels > 70', async () => {
    mockGPTResponse('Hello world.');
    await service.formatText('hello world', makeSettings({
      formattingLevel: 85,
      appContext: { appName: 'Slack', windowTitle: '#general' },
    }));

    const call = mockCreate.mock.calls[0][0];
    expect(call.messages[1].content).toContain('[Context:');
    expect(call.messages[1].content).toContain('Application: Slack');
    expect(call.messages[1].content).toContain('Window: #general');
    expect(call.messages[1].content).toContain('hello world');
  });

  it('does not inject app context for levels <= 70', async () => {
    mockGPTResponse('Hello world.');
    await service.formatText('hello world', makeSettings({
      formattingLevel: 50,
      appContext: { appName: 'Slack', windowTitle: '#general' },
    }));

    const call = mockCreate.mock.calls[0][0];
    expect(call.messages[1].content).toBe('hello world');
    expect(call.messages[1].content).not.toContain('[Context:');
  });

  it('does not inject app context when custom formatPrompt is set', async () => {
    mockGPTResponse('Formatted.');
    await service.formatText('hello world', makeSettings({
      formattingLevel: 85,
      formatPrompt: 'Custom prompt.',
      appContext: { appName: 'Slack', windowTitle: '#general' },
    }));

    const call = mockCreate.mock.calls[0][0];
    expect(call.messages[1].content).toBe('hello world');
  });

  it('throws error when OpenAI returns empty content', async () => {
    mockGPTResponse(null);
    await expect(
      service.formatText('hello world', makeSettings({ formattingLevel: 50 }))
    ).rejects.toThrow('No response received from GPT');
  });

  it('trims the GPT response', async () => {
    mockGPTResponse('  Hello world.  ');
    const result = await service.formatText('hello world', makeSettings({ formattingLevel: 50 }));
    expect(result).toBe('Hello world.');
  });

  it('scales temperature with formatting level', async () => {
    mockGPTResponse('Test.');
    await service.formatText('test', makeSettings({ formattingLevel: 100 }));

    const call = mockCreate.mock.calls[0][0];
    expect(call.temperature).toBeCloseTo(0.3);
  });

  it('uses minimum temperature of 0.1 for low formatting levels', async () => {
    mockGPTResponse('Test.');
    await service.formatText('test', makeSettings({ formattingLevel: 1 }));

    const call = mockCreate.mock.calls[0][0];
    expect(call.temperature).toBeCloseTo(0.1);
  });
});
