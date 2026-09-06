import { describe, expect, it } from "vitest";
import { screenLine, MAX_LINE_LENGTH } from "../src/services/banterFilter.js";
import { LINE_BANK } from "../src/content/lineBank.js";

/**
 * The filter's job is to keep generated text from ever sounding like a real
 * driving instruction. These cases matter more than most: a false negative
 * here reaches a speaker in a moving car.
 */
describe("navigation phrasing", () => {
  const mustReject = [
    "Turn left onto Maple Street.",
    "In 500 feet, turn right.",
    "Take the next exit.",
    "Make a u-turn when possible.",
    "Merge onto the highway.",
    "Keep right at the fork.",
    "Your destination is on the left.",
    "At the roundabout, take the second exit.",
    "Continue straight for 2 miles.",
    "In 1.5 kilometers you will arrive.",
  ];

  for (const text of mustReject) {
    it(`rejects "${text}"`, () => {
      const result = screenLine(text);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.reason).toBe("navigation_phrasing");
    });
  }

  const mustAllow = [
    "Turn coming up. This is the part where everything could go wrong.",
    "I hope whoever designed this intersection is proud of themselves.",
    "Oh, this turn? Child's play. Watch this.",
    "This is a lot of turn for one road.",
    "I saw this turn coming a mile away. Literally, there's a sign.",
    "A minor detour. I meant to do that.",
    "This road just keeps going, doesn't it.",
  ];

  for (const text of mustAllow) {
    it(`allows commentary: "${text.slice(0, 40)}..."`, () => {
      expect(screenLine(text).ok).toBe(true);
    });
  }
});

describe("general screening", () => {
  it("rejects empty and whitespace-only lines", () => {
    expect(screenLine("").ok).toBe(false);
    expect(screenLine("   \n  ").ok).toBe(false);
  });

  it("rejects lines too long to speak in the gap they were written for", () => {
    const result = screenLine("a".repeat(MAX_LINE_LENGTH + 1));
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("too_long");
  });

  it("rejects profanity", () => {
    const result = screenLine("Well that's a load of shit.");
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe("blocked_term");
  });

  it("does not trip on innocent words containing a blocked substring", () => {
    // The classic false positive: substring matching would kill both of these.
    expect(screenLine("Scunthorpe is lovely this time of year.").ok).toBe(true);
    expect(screenLine("I'm feeling classic anxiety about this bridge.").ok).toBe(true);
  });

  it("rejects the model answering about the task instead of doing it", () => {
    for (const text of ["Sure! Here are two lines of banter.", "Dan: I don't like this at all."]) {
      const result = screenLine(text);
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.reason).toBe("meta_commentary");
    }
  });

  it("normalises whitespace on accepted lines", () => {
    const result = screenLine("  Look at us,   just   cruising.  ");
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.text).toBe("Look at us, just cruising.");
  });
});

/**
 * The bank is the fallback the filter's output is compared against, so if a
 * shipped line would fail the filter, the two have drifted apart.
 */
describe("the shipped bank passes its own filter", () => {
  for (const line of LINE_BANK) {
    it(`${line.id}`, () => {
      expect(screenLine(line.text).ok).toBe(true);
    });
  }
});
