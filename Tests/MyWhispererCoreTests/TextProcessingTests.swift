import Foundation
import Testing
@testable import MyWhispererCore

@Suite struct OutputParserTests {
    @Test func extractsTaggedOutput() {
        #expect(OutputParser.extract("<output>Hello there.</output>") == "Hello there.")
    }

    @Test func ignoresTextOutsideTags() {
        #expect(OutputParser.extract("Sure! Here you go:\n<output>\nHi.\n</output>\nHope that helps") == "Hi.")
    }

    @Test func acceptsMissingClosingTag() {
        #expect(OutputParser.extract("<output>Stopped at sequence") == "Stopped at sequence")
    }

    @Test func returnsNilWithoutTags() {
        #expect(OutputParser.extract("Here is the cleaned text: Hi.") == nil)
    }

    @Test func emptyOutputIsEmptyString() {
        #expect(OutputParser.extract("<output></output>") == "")
    }
}

@Suite struct HallucinationFilterTests {
    @Test(arguments: [
        "Thank you for watching.",
        "Untertitel der Amara.org-Community",
        "Untertitel im Auftrag des ZDF, 2017",
        "...",
        "T T T T",
        "   ",
    ])
    func dropsHallucinations(_ text: String) {
        #expect(HallucinationFilter.clean(text) == "")
    }

    @Test(arguments: ["Thank you.", "Vielen Dank.", "Thanks for watching my dog tomorrow!", "OK"])
    func keepsRealSpeech(_ text: String) {
        #expect(HallucinationFilter.clean(text) == text)
    }

    @Test func stripsCreditSentenceButKeepsSpeech() {
        let text = "Let's ship it on Monday. Untertitel der Amara.org-Community"
        #expect(HallucinationFilter.clean(text) == "Let's ship it on Monday.")
    }
}

@Suite struct SnippetExpanderTests {
    let snippets = [
        Snippet(trigger: "my calendar link", expansion: "https://cal.com/alex"),
        Snippet(trigger: "my email", expansion: "me@example.com"),
        Snippet(trigger: "my work email", expansion: "alex@work.com"),
    ]

    @Test func wholeDictationIsReplacedWithoutPunctuation() {
        #expect(SnippetExpander.expand("My calendar link.", snippets: snippets) == "https://cal.com/alex")
    }

    @Test func inlineCueIsReplaced() {
        #expect(SnippetExpander.expand("You can book here: my calendar link. Thanks!", snippets: snippets)
                == "You can book here: https://cal.com/alex. Thanks!")
    }

    @Test func longestTriggerWins() {
        #expect(SnippetExpander.expand("Send it to my work email please", snippets: snippets)
                == "Send it to alex@work.com please")
    }

    @Test func doesNotMatchInsideWords() {
        #expect(SnippetExpander.expand("Check my emails later", snippets: snippets) == "Check my emails later")
    }

    @Test func expansionWithTemplateCharactersIsLiteral() {
        let s = [Snippet(trigger: "price", expansion: "$10 \\ month")]
        #expect(SnippetExpander.expand("The price is fine", snippets: s) == "The $10 \\ month is fine")
    }
}

@Suite struct InsertionFormatterTests {
    @Test func addsSpaceAfterWord() {
        #expect(InsertionFormatter.format("and more.", before: "Hello", fixCapitalization: false) == " and more.")
    }

    @Test func noSpaceAfterWhitespaceOrOpeningBracket() {
        #expect(InsertionFormatter.format("hi", before: "Hello ", fixCapitalization: false) == "hi")
        #expect(InsertionFormatter.format("hi", before: "(", fixCapitalization: false) == "hi")
    }

    @Test func noSpaceBeforePunctuation() {
        #expect(InsertionFormatter.format(", right?", before: "Hello", fixCapitalization: false) == ", right?")
    }

    @Test func capitalizesAtSentenceStartForRawText() {
        #expect(InsertionFormatter.format("hello there", before: nil, fixCapitalization: true) == "Hello there")
        #expect(InsertionFormatter.format("next one", before: "Done. ", fixCapitalization: true) == "Next one")
    }

    @Test func lowercasesCommonWordMidSentence() {
        #expect(InsertionFormatter.format("The rest", before: "and then", fixCapitalization: true) == " the rest")
    }

    @Test func lowercasesContinuationEvenAfterCleanup() {
        #expect(InsertionFormatter.format("And then we ship.", before: "The tests pass now", fixCapitalization: false)
                == " and then we ship.")
        // After a finished sentence the model's capital stays.
        #expect(InsertionFormatter.format("And then we ship.", before: "Done.", fixCapitalization: false)
                == " And then we ship.")
        #expect(InsertionFormatter.format("Berlin rocks.", before: "I think", fixCapitalization: false)
                == " Berlin rocks.")
    }

    @Test func keepsNamesAndAcronymsMidSentence() {
        #expect(InsertionFormatter.format("Berlin is nice", before: "I think", fixCapitalization: true) == " Berlin is nice")
        #expect(InsertionFormatter.format("API docs", before: "read the", fixCapitalization: true) == " API docs")
        #expect(InsertionFormatter.format("I agree", before: "well", fixCapitalization: true) == " I agree")
    }
}

@Suite struct TextStatsTests {
    @Test func countsWords() {
        #expect(TextStats.wordCount("Hello there, how's it going?") == 5)
        #expect(TextStats.wordCount("") == 0)
    }

    @Test func summaryComputesWPMAndStreak() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let day: TimeInterval = 86_400
        let entries = [
            HistoryEntry(date: now, rawText: "", finalText: String(repeating: "word ", count: 150), audioSeconds: 60, transcriptionModel: "m"),
            HistoryEntry(date: now - day, rawText: "", finalText: "one two", audioSeconds: 1, transcriptionModel: "m"),
            HistoryEntry(date: now - 3 * day, rawText: "", finalText: "gap", audioSeconds: 1, transcriptionModel: "m"),
        ]
        let summary = TextStats.summarize(entries, now: now, calendar: calendar)
        #expect(summary.words == 153)
        #expect(summary.dictations == 3)
        #expect(summary.dayStreak == 2)
        #expect(summary.wordsPerMinute == 148)
        #expect(summary.minutesSaved == 3)
    }
}

@Suite struct AudioClipTests {
    @Test func wavRoundTrip() throws {
        let clip = AudioClip(samples: [0, 1000, -1000, Int16.max, Int16.min], sampleRate: 16_000)
        let decoded = try #require(AudioClip(wav: clip.wavData))
        #expect(decoded == clip)
        #expect(clip.wavData.count == 44 + 10)
    }

    @Test func silenceHasNoVoicedAudio() {
        let silence = AudioClip(samples: Array(repeating: 3, count: 16_000))
        #expect(AudioLevel.voicedSeconds(silence) == 0)
    }

    @Test func toneIsVoiced() {
        let tone = makeTone()
        #expect(AudioLevel.voicedSeconds(tone) > 0.9)
    }
}
