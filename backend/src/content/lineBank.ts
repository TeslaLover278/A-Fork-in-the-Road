/**
 * Server-side mirror of Content/BanterLineBank.swift.
 *
 * It has two jobs. It is the payload for /v1/content/line-bank, so jokes can
 * ship without an App Store release; and it is the fallback the banter route
 * serves whenever generation is unavailable, times out, or gets filtered —
 * which means the server degrades to exactly the behaviour the client
 * already has offline, rather than to an error.
 *
 * Bump CONTENT_VERSION whenever lines or personas change; clients cache on it.
 */
export const CONTENT_VERSION = 2;

export const BANTER_CATEGORIES = [
  "tripStart",
  "upcomingTurn",
  "rerouting",
  "arrival",
  "idleChatter",
] as const;

export type BanterCategory = (typeof BANTER_CATEGORIES)[number];

export interface BankLine {
  id: string;
  personaId: string;
  category: BanterCategory;
  text: string;
}

const RAW: Record<string, Record<BanterCategory, string[]>> = {
  dez: {
    tripStart: [
      "Okay. Okay okay okay. We're doing this. Everybody stay calm.",
      "New trip, new opportunities for something to go horribly wrong.",
      "I've already found four things to worry about and we haven't left the driveway.",
      "Seatbelts, check. Snacks, check. My will to live, questionable.",
      "Statistically speaking, most drives end fine. Most.",
      "I read that this route has a stop sign. A STOP sign, Vale.",
      "Here we go. I'll be narrating the whole thing, just so there's a record.",
      "Deep breaths. We can do this. Probably.",
      "I already don't like the look of that sky.",
      "Buckle up. Not a suggestion. A prophecy.",
    ],
    upcomingTurn: [
      "Turn coming up. This is the part where everything could go wrong.",
      "Okay, stay focused, there's a turn approaching and my heart cannot handle surprises.",
      "This next turn looks tighter than the last one. I don't love it.",
      "I'm just going to close my eyes for this next part. Kidding. Unless.",
      "Here it comes. The turn. THE turn.",
      "I hope whoever designed this intersection is proud of themselves.",
      "Slow down, slow down, SLOW— okay, you're fine, you're fine.",
      "This is a lot of turn for one road.",
    ],
    rerouting: [
      "Wait, WAIT. Are we off course? Are we lost? Is this a whole thing now?",
      "I knew it. I knew something would happen. I'm never right about good things, only this.",
      "Recalculating. That word has never once meant anything good.",
      "This is fine. This is FINE. We are simply... exploring.",
      "New route, same anxiety.",
      "Did we miss the turn, or did the turn miss us? I need to know who to blame.",
    ],
    arrival: [
      "We made it. We actually made it. I can't believe it either.",
      "Alive and parked. Two things I wasn't sure about ten minutes ago.",
      "Arrival achieved. Someone write this down.",
      "I'm going to need a minute. That was a whole journey, emotionally.",
      "We're here! I'm choosing to feel proud instead of just relieved.",
    ],
    idleChatter: [
      "This road just keeps going, doesn't it. Just going and going.",
      "Nothing's happening and somehow that's making me more nervous.",
      "I'm going to assume everything's fine because the alternative is exhausting.",
      "This is a very long straight road for something to go wrong on.",
      "Are we still on the right road? I'm asking for me.",
      "I've started narrating the scenery to stay calm. There's a tree. Another tree.",
    ],
  },
  vale: {
    tripStart: [
      "Relax, Dez. I've driven this exact route in my head a thousand times.",
      "Called it. We're going. I said we'd go and here we are.",
      "This is going to be the smoothest drive of your life. You're welcome in advance.",
      "I don't do nervous. I do 'in control.'",
      "Fun fact: I've never once been lost. Ever.",
      "Let the record show I predicted clear roads today.",
      "Buckle up, sure, but mostly because I drive like a legend.",
      "We're basically already there. Vibes.",
      "Dez, breathe. One of us has to be the calm one, and it's obviously me.",
      "I've got a good feeling about this drive. I always do.",
    ],
    upcomingTurn: [
      "Oh, this turn? Child's play. Watch this.",
      "I saw this turn coming a mile away. Literally, there's a sign.",
      "Handle this one smooth. Make it look effortless. Like me.",
      "This is exactly where I'd turn if I were, you know, always right.",
      "Easy turn. I've made harder decisions picking a lunch spot.",
      "Watch and learn, Dez. This is what confidence looks like.",
      "Nailed it before we even took it. That's just how I operate.",
      "This turn doesn't stand a chance against us.",
    ],
    rerouting: [
      "Relax, this was basically the plan the whole time.",
      "A minor detour. I meant to do that.",
      "New route, new chance for me to be right again.",
      "This is just the scenic version of being correct.",
      "I'm choosing to call this 'optimizing,' not 'lost.'",
      "See, this is why you trust the process. My process.",
    ],
    arrival: [
      "And that, Dez, is how it's done.",
      "Arrived exactly on schedule, exactly as I predicted.",
      "Another flawless drive in a long line of flawless drives.",
      "You can applaud now. I'll wait.",
      "Told you we'd get here in one piece. I tell you a lot of things and they're all true.",
    ],
    idleChatter: [
      "Look at us, just cruising. Like professionals.",
      "This is the part of the drive where I get to be smug in peace.",
      "No turns, no drama, just me being effortlessly right about the route.",
      "I could drive this stretch with my eyes closed. Don't worry, I won't.",
      "Nice long straightaway. Perfect for reflecting on how correct I usually am.",
      "This is what a good route looks like. You're welcome.",
    ],
  },
};

/**
 * Ids are stable and content-derived (`dez.tripStart.0`) rather than random,
 * so a client can cache a bank, re-fetch it later, and still recognise which
 * lines it has recently played.
 */
export const LINE_BANK: BankLine[] = Object.entries(RAW).flatMap(([personaId, byCategory]) =>
  BANTER_CATEGORIES.flatMap((category) =>
    (byCategory[category] ?? []).map((text, index) => ({
      id: `${personaId}.${category}.${index}`,
      personaId,
      category,
      text,
    })),
  ),
);

export function bankLines(personaId: string, category: BanterCategory): BankLine[] {
  return LINE_BANK.filter((l) => l.personaId === personaId && l.category === category);
}

/** Picks a line, preferring ones the caller hasn't heard recently. */
export function pickBankLine(
  personaId: string,
  category: BanterCategory,
  exclude: ReadonlySet<string> = new Set(),
): BankLine | undefined {
  const candidates = bankLines(personaId, category);
  if (candidates.length === 0) return undefined;
  const fresh = candidates.filter((l) => !exclude.has(l.id));
  const pool = fresh.length > 0 ? fresh : candidates;
  return pool[Math.floor(Math.random() * pool.length)];
}
