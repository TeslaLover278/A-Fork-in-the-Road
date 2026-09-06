import Foundation

/// The actual joke content, organized by persona + trigger category. This
/// is deliberately just data — adding more lines later is appending to the
/// arrays below, never touching BanterEngine's selection logic.
final class BanterLineBank {
    static let shared = BanterLineBank()

    private let lines: [BanterLine]

    init(lines: [BanterLine] = BanterLineBank.defaultLines) {
        self.lines = lines
    }

    /// Picks a random line for the given persona/category, avoiding recently
    /// used lines when possible. Falls back to allowing a repeat rather than
    /// returning nil if every line in that bucket was recently used.
    func line(persona: String, category: BanterCategory, excluding: [UUID]) -> BanterLine? {
        let candidates = lines.filter { $0.personaID == persona && $0.category == category }
        guard !candidates.isEmpty else { return nil }
        let fresh = candidates.filter { !excluding.contains($0.id) }
        let pool = fresh.isEmpty ? candidates : fresh
        return pool.randomElement()
    }
}

extension BanterLineBank {
    static let defaultLines: [BanterLine] = {
        var lines: [BanterLine] = []

        func add(_ persona: String, _ category: BanterCategory, _ texts: [String]) {
            lines.append(contentsOf: texts.map { BanterLine(personaID: persona, category: category, text: $0) })
        }

        add("dan", .tripStart, [
            "Okay. Okay okay okay. We're doing this. Everybody stay calm.",
            "New trip, new opportunities for something to go horribly wrong.",
            "I've already found four things to worry about and we haven't left the driveway.",
            "Seatbelts, check. Snacks, check. My will to live, questionable.",
            "Statistically speaking, most drives end fine. Most.",
            "I read that this route has a stop sign. A STOP sign, Harry.",
            "Here we go. I'll be narrating the whole thing, just so there's a record.",
            "Deep breaths. We can do this. Probably.",
            "I already don't like the look of that sky.",
            "Buckle up. Not a suggestion. A prophecy."
        ])
        add("harry", .tripStart, [
            "Relax, Dan. I've driven this exact route in my head a thousand times.",
            "Called it. We're going. I said we'd go and here we are.",
            "This is going to be the smoothest drive of your life. You're welcome in advance.",
            "I don't do nervous. I do 'in control.'",
            "Fun fact: I've never once been lost. Ever.",
            "Let the record show I predicted clear roads today.",
            "Buckle up, sure, but mostly because I drive like a legend.",
            "We're basically already there. Vibes.",
            "Dan, breathe. One of us has to be the calm one, and it's obviously me.",
            "I've got a good feeling about this drive. I always do."
        ])

        // .upcomingTurn has no static lines: the turn itself is delivered by
        // DirectionAnnouncementBank's templates instead, since that content
        // needs to embed the real instruction and distance. See
        // BanterEngine.announceManeuver.

        add("dan", .rerouting, [
            "Wait, WAIT. Are we off course? Are we lost? Is this a whole thing now?",
            "I knew it. I knew something would happen. I'm never right about good things, only this.",
            "Recalculating. That word has never once meant anything good.",
            "This is fine. This is FINE. We are simply... exploring.",
            "New route, same anxiety.",
            "Did we miss the turn, or did the turn miss us? I need to know who to blame."
        ])
        add("harry", .rerouting, [
            "Relax, this was basically the plan the whole time.",
            "A minor detour. I meant to do that.",
            "New route, new chance for me to be right again.",
            "This is just the scenic version of being correct.",
            "I'm choosing to call this 'optimizing,' not 'lost.'",
            "See, this is why you trust the process. My process."
        ])

        add("dan", .arrival, [
            "We made it. We actually made it. I can't believe it either.",
            "Alive and parked. Two things I wasn't sure about ten minutes ago.",
            "Arrival achieved. Someone write this down.",
            "I'm going to need a minute. That was a whole journey, emotionally.",
            "We're here! I'm choosing to feel proud instead of just relieved."
        ])
        add("harry", .arrival, [
            "And that, Dan, is how it's done.",
            "Arrived exactly on schedule, exactly as I predicted.",
            "Another flawless drive in a long line of flawless drives.",
            "You can applaud now. I'll wait.",
            "Told you we'd get here in one piece. I tell you a lot of things and they're all true."
        ])

        add("dan", .idleChatter, [
            "This road just keeps going, doesn't it. Just going and going.",
            "Nothing's happening and somehow that's making me more nervous.",
            "I'm going to assume everything's fine because the alternative is exhausting.",
            "This is a very long straight road for something to go wrong on.",
            "Are we still on the right road? I'm asking for me.",
            "I've started narrating the scenery to stay calm. There's a tree. Another tree."
        ])
        add("harry", .idleChatter, [
            "Look at us, just cruising. Like professionals.",
            "This is the part of the drive where I get to be smug in peace.",
            "No turns, no drama, just me being effortlessly right about the route.",
            "I could drive this stretch with my eyes closed. Don't worry, I won't.",
            "Nice long straightaway. Perfect for reflecting on how correct I usually am.",
            "This is what a good route looks like. You're welcome."
        ])

        return lines
    }()
}
