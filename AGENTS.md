# Synmergia - Developer Notes for AI Agents

> **Purpose:** This file is a **stable reference** for AI agents
> working on Synmergia. It documents code conventions, architecture,
> and patterns that don't change frequently.
>
> **What this file is NOT:** An operational log, debugging status,
> or session history. (Session notes go in `labs/TASKS.md`.)

  > **Last updated 2026-11-05 (mystery gate round):** THE OVERLOOKED PIPE CLOSED (owner's ISO-9001-grade audit quip): the owner flagged that the ancient movers were defined as DORMANT but no doc ever wrote what wakes them -- the dormant-unlock economy was a gap in the world PRDs, "a crucial overlooked pipe", and it must be defined IN synmergia prds and crosslinked to the investor materials because "our sense of mystery *is* the momentum, everywhere." LANDED: labs/prompts/gemini_vehicles.md grew THE MYSTERY GATE (canon, the ancients' wake-keys): every server-unlocked thing (ancient movers, sealed gates, hidden abilities, dormant world physics, anything) holds its wake-key behind the world, never the store, through THE FIVE WAKE-KEYS -- (1) the server PUZZLE (world-text riddles solved by players), (2) the TRAM EFFORT (honest use is the key: trips walked, hauls made, crowds carried), (3) the OBSERVATION (the patient watcher: things noticed where nobody looks), (4) the INTERACTION (ritual gestures, offerings, tablet statutes in right order), (5) the PURE LUCK (it wakes itself; who stood there was the key). THE SEALED KEYS law (owner verbatim: "some even the devs don't know"): some wake conditions are written ONLY server-side, absent from design docs by design -- the team discovers alongside the players; docs may speak of an ancient's family and laws, never its sealed keys. THE LAW: nothing purchasable opens a wake-key -- kits, modifiers, seats, blessings, none of the twenty priced rows wake the unwoken. CROSSLINKS: prd-ocean-depths's ferry law grew its wake-key line (the schedule runs from boot -- the ONE wake-key carved in the open); the investor paragraph grew its clause (a Mystery Gate that prices nothing); the Concord's Table stands unstained by the gate (twenty rows priced, none wakes the unwoken). Bench now NINETEEN rows (Mystery Gate, home: vehicles seed). DOC-ONLY round: zero .tres, zero service changes, the pack export stands.

  > **Last updated 2026-11-05 (tide-mender + concord table round):** SPITBALLS #16 AND #17 AGREED (owner yay + yay). #16 prd sec 29 THE TIDE-MENDER TRADE -- the owner ABSTRACTED the kit pitch to VEHICLE MAINTENANCE AND REPAIR for every mover (sea won't be the only traveling mechanism): vessels, mounts and tack, gliders, breather helmets, and the woken platforms (Conduit Glider / Islet Lifter / Caravan Crawler on the gemini vehicles seed rails; mounts/gliders/helmets explicitly named by the owner). THE TWO MOVERS, now canon wherever vehicles are written: PERSONAL MOVERS (player-owned: mounts on the RideService ledger, platforms woken by YOUR tablet, gliders, helmets) vs ANCIENT MOVERS (the server-unlocked ancients: the ferries -- the ferry honesty law's "server-owned vessel" is the first verse -- dormant ruin movers, the islets' orb machines; civic bills only, never a personal SKU, never sold to a player). Canon edits landed: labs/prompts/gemini_vehicles.md grew "The two movers" canon block; labs/prd-ocean-depths.md's ferry honesty law grew the two-movers verse (item 0); every future world-building PRD speaking of vehicles makes the distinction before it prices anything. NO TECHNOLOGY LAW held: the vehicles pack already wrote "woken, never built or fueled, no engines/wheels/cabins" -- so the owner's MODIFIERS-extension (no engines concept in synmergia) dresses as verse work, not tech tuning. TRADE LAWS: repairs FREE at stations forever (Fenwick's pending tide-side service is the trade's first desk); the Mender's Kit = craftable consumable at Fenwick's bench from honest salvage, one field mend, identical kit on the Concord shelf ~$0.50 (the waystone row's sink shape, two-way); MODIFIERS never move a combat rate (not one tick), never raise a travel-speed ceiling (movement profiles stay data), buy only capability/comfort verbs (deep-lung verse, quiet sail, grip), on the chartered shape with an authored visible toll, provenance EARNED/BOUGHT on the ledger; IMPLEMENTATION SEAT gated on movers that exist (kit .tres + shelf row + MEND sink family, Fenwick's station, wear books); kit price build-seat, veto reserved. #17 prd sec 30 THE CONCORD'S TABLE (spitball pitch: "the doc's own money ladder") -- THE WHOLE MACHINE CANONICALIZED on one page: a twenty-row table, one row per seat, each carrying SKU / how it is sold / price felt / sink kind / earn path (the free door) / section home, from the Charter (~$8.99, 300 earned sigils two-way) through Mythos grades, dyes, locker, heraldry, Lucky, the Peal, expedition tiers, titles, the resurrection ticket, the waystone, the homestead, the pub's clock, the sponsor stage, grudge and glad seats, the ankh blessing, the mender's kit and mover modifiers; the read law: money buys the clock / presence / the now, and the count is the pitch -- TWENTY rows priced, NONE turns a stat on by purchase; owner called it "refresh and canonicalization of this beast" (the psy doc turned serious). Investor paragraph grew its clause (the trade + the table). Bench now EIGHTEEN rows. DOC-ONLY round: zero .tres, zero service changes, the pack export stands.

  > **Last updated 2026-11-05 (ankh round):** SPITBALL #15 AGREED (OWNER PITCH, "the easy win"; Buffy yay + law dress): prd sec 27 THE CONSECRATED ANKH -- HOUSE RESPAWN, the death screen's third door. RAILS VERIFIED: the ankh item ALREADY EXISTS -- DwellingService prices it gold (100k) and the sec 19 homestead rails carry the placement; what never existed is the BLESSING (a plain ankh is an inert device), so this section authors it. SEAT 1 THE DOOR: a fallen fighter with a CONSECRATED ankh sees "Ankh at Home" on the death screen -- stand up at the ankh's placement in the held cottage; the fall never teleports the living (a revival door, never a travel door, the sec 20 scope keeps them separate); the cooldown book is read BEFORE the door shows green -- a cold ankh greys with a tooltip (the social doc's parked shape, greyed never hidden), remaining time printed, looking costs nothing (preview never debits), no charge takes while dim. SEAT 2 TWO BLESSINGS ONE ANKH THE CLOCKS HONEST (the owner's exact shape): THE EARN -- THE DEDICATION: after achieving a house the clergy opens a dedication chain (a couple of WEEKS of earned deeds, the sec 16 week-per-tier shape) gated on the actual DwellingService dwelling record (never a receipt) on the real quest rails -- the earned blessing runs the FASTER clock, house respawn every FOUR HOURS; THE BUY -- THE CHARTERED BLESSING: money skips the dedication and consecrates TODAY, and the bought blessing carries the toll in its only lawful dress, TIME (the sec 16 chartered shape verbatim) -- house respawn every SIX HOURS; same door as the grinder's, the grind keeps the sooner clock, the wallet buys the door NOW, nobody buys a better ceiling. LAWS: ONE blessing per homestead, PERMANENT, never a lease (purchases-permanent), stamped EARNED (4h) / BOUGHT (6h) in the account ledger through the tx roots beside the dwelling record (provenance reused, the sec 10 purse law); the cooldown is ONE keyed book per account on CooldownService's own book (NOT the sec 14 central roll-time modifier -- a clock, never a die), starts at use, prints concrete remaining time; the blessing is keyed to the DWELLING not the plot -- the sec 19 deed move carries it intact (earned free first move, chartered +20% as already authored, never re-billed); convenience never power (no XP gain, no gold-per-death, no stat, no combat rate touched); death NEVER loses its free doors (zone spawn + the shipped stand-up stay every account's constant floor -- the ankh is a third door, never a toll-gated only door). PRICE FELT: one-time ~$4.99 (the Charter's own price point on the existing webhook processor SKUs); exact cent a build-seat number, owner's veto reserved. IMPLEMENTATION SEAT (build round): door-routing on RespawnService's death-screen reader (ownership + ankh-placed + blessing read from DwellingService), the cooldown book on the account ledger via the tx roots, the dedication quest chain on the quest .tres rails, one webhook SKU + a BLESS sink row (no-fake-sinks: the grant leg ships with the row), the blessing field in the provenance print, the death-screen line + a11y remaining-time text. NUMBERS: investor renumbered sec 27 -> 28 (the stool rides inside it); the stool bench row home now §28; bench now SIXTEEN rows (the ankh). DOC-ONLY round: zero .tres, zero service changes, the pack export stands.
  > **Last updated 2026-11-05 (grudge + glad ring round):** SPITBALLS #13 AND #14 AGREED (#13 Buffy pitch + owner yay, TBA cleared; #14 the OWNER'S GLADIATOR PITCH -- "gladiator style -- spectators can wager on matches. Certain duels for high profile players are planned and announced ahead of time, multiple rounds like boxing, they make out well, we make out well" -- Buffy yay + law dress). prd sec 25 THE GRUDGE BOOK (the stool's Leg 4 seats landed): SEAT 1 THE REMATCH BELFRY (the duel never changes and never costs anything -- same arena ladder, same consent, BASE RATES; the rite sold is the event around it: for a bout between two fighters on each other's heated-rival list a zone bell + a banner in the sec 15 dress -- authored template sentence from service record, "Belfry: Kestrel and Oldwren settle their grudge at the Salt Pans -- 2 losses in the book"; NO FREE TEXT; one-time consumable on the pot charm's impulse shape ~$1.25, deed-or-buy two-way); SEAT 2 THE GRUDGE BOOK PROPER (the shipped ring buffer free -- twenty bouts FIFO; new free rail: ANY player may PLEDGE one active rival server-truth, both fighters see it, zero cost; the PAID leg is CAPACITY -- each extra pledge a spare deed-earnable-in-a-week row or bought on the chartered family, the sec 16 shape; capacity never a stat, everyone owns one pledge, the pledge is never sold as privilege); SEAT 3 THE SETTLED SCORE (a pledged grudge settled by winning mints the PREFIX "the Unforgiving" deed by construction -- NOBODY BUYS AN HONOR; the buy route mints at most the suffix "the Spiteful" -- the baron's shape). SPITE FIREWALL: nobody buys power over another player -- no curses, no debuffs, no enemy-facing anything ("no enemy-facing aura debuffs, no social engineering" verbatim); spite celebrated never weaponized; Rematch + all consent paths free forever; banners server truth; AppFirewall one-duel limit untouched; spectate stays parked greyed-never-hidden. RAILS VERIFIED: RECENT_PLAYERS per bout_ended carries zone/mode/result/when/head-to-head, ONE-CLICK REMATCH IS SHIPPED, consent paths hard law. prd sec 26 THE GLAD RING: SEAT 1 THE GLADNIGHT (the venue clock on the sec 22 Anchor Room shape verbatim -- held pub evening runs the Glad Ring free on the deed allotment, money buys longer clock + extra announced weeks, never floors); SEAT 2 THE MADE BOUT (a fighter with an ACTIVE sec 25 pledge makes the bout: scheduled to an almanac day, announced ahead on the schedule board, both fighters consent-signed, BEST-OF-FIVE rounds with a 60-second break, the head-to-head line printed from record; no free text); SEAT 3 THE BOOK (GOLD ONLY -- real money never places a bet, no sigils on the felt, the RMT firewall; odds SERVER TRUTH from the same head-to-head ledger, authored template lines ("the pans book called it 3-to-1"); bets open at the card and CLOSE AT THE FIRST BELL, settle per round and for the bout; per-account per-almanac-day wager cap, the QoS family's shape); SEAT 4 THE PURSE AND THE RAKE (purse = pool minus rake to the winner; RAKE authored 10% GOLD to Concord, a new audited sink row beside the roll board; fighters may hang a sponsor's name on the card -- the sec 23 dress, service-record credit, no custom message; THE COMBAT FIREWALL VERBATIM -- duels/made bouts/rated rooms/the Book read base rates always, no rate moves by bet, bell or banner); THE UNDISPUTED (a made-bout champion mints the suffix deed by construction, winning is a verb, no purchase route exists for it; prefixes stay sec 25's deed-only). LAWS: both fighters consent and either may walk before the first bell; no fighter bets their own bout; rounds format identical for every bout; rake authored and visible. IMPLEMENTATION SEATS (build rounds): pledge leg on the recent-players ledger (ids + standing stamp only), belfry rite .tres + sink row + zone event + banner through the sec 15 rails, pledge SKU on the chartered family, rounds + break clock on the duel lifecycle, card/odds reader beside the travel board, wager window + cap through the tx roots, rake + Gladnight sink rows, made-bout board. NUMBERS: investor renumbered sec 24 -> 27 (the investor stool rides inside it); the stool's Leg 4 TBA line now reads §25 (the Grudge Book); bench now FIFTEEN rows (Grudge + Glad Ring). DOC-ONLY round: zero .tres, zero service changes, the pack export stands.
  > **Last updated 2026-11-05 (stool round):** SPITBALL #12 AGREED (Buffy pitch, owner yay + the owner's fourth leg added): prd sec 24 THE INVESTOR STOOL -- the one-paragraph answer stays whole; a new subsection reorganizes the investor read into FOUR focal answers, one per investor kind: LEG 1 THE HEARTS ANSWER (the ego economy -- players buy PRESENCE, never power: the pub's door, the name over the shard's +10% stage, the waystone that remembers a place; emotional spend = no P2W lawsuit surface, no whale churn cliff, legends retain); LEG 2 THE MARGIN ANSWER (the cost side -- ~$0.04 per DAU-month, ~$0.35 per CCU-month at 10k, dated anchors, ~2,000 monthly payers cover infra, the rest is margin or labor; costs measured not vibes); LEG 3 THE CADENCE ANSWER (the machine -- packs author income against the curve by signed law, the cap lifts on data, cadence contractual; investors underwrite a schedule not a hope); LEG 4 THE GRUDGE ANSWER -- THE OWNER'S FOURTH LEG, THE SPITE MODEL, TBA (revenge, grudges, rivalry -- folks spend before thinking when a name is in front of them; the RAILS already stand: the recent-players heated-rival list + the one-click REMATCH are this psychology's front door; the concrete spend seats are DELIBERATELY TBA, landing on their own spitball and inheriting every law -- no stat purchase, no free text, the authored tradeoff; the investors' line: impulse spend is the cheapest product we do not yet sell). BENCH: now THIRTEEN rows (stool row AGREED, doc-only). DOC-ONLY round: zero .tres, zero service changes, the pack export stands.
  > **Last updated 2026-11-05 (boost bump round):** SPITBALL #11 AMENDED BY OWNER VETO (stingy rejected): the Sponsor Stage rate ceiling authors +5% -> +10% ("5% is too low and weird stingy"); the ceiling still NEVER moves by purchase (a second $20 during a live stage STILL only extends the clock, never makes +20%); the deed route rides the same +10% (grind unlocks the identical stage, the two-way slot price unchanged); the sec 23 honest-seam line, the implementation seat and the combat firewall carry the new number verbatim. Historical round notes keep their contemporaneous +5% lines. DOC-ONLY round: zero .tres, zero service changes, the pack export stands.
  > **Last updated 2026-11-05 (pub + sponsor round):** SPITBALLS #10 AND #11 AGREED IN ONE BREATH (owner yay on ALL of #10 -- "Love it! ... yay on it all! Let's run it" -- then the owner pitched #11 sponsors; Buffy yay + law dress on both; both landed this round). prd sec 22 THE ANCHOR ROOM (the owner's own framing: "you pay a 'tax' and synmergia allows you to open the pub") -- FOUR SEATS: (1) THE PUB TAX, the room clock (a deed-earned weekly allotment opens the pub several held evenings a week FREE, the sec 16 week-per-tier shape; money buys MORE CLOCK and LONGER HOLDS, never bigger rooms, never broker content; payable from the sec 13 vault rank-gated or the holder's ledger); (2) THE TAVERN LICENSE (a held room DECLARES itself OPEN, the door lists on the world's travel board, anyone may walk in; the deed plate's name IS the advertisement -- no custom signage exists to buy); (3) THE FURNISHED NIGHT (the sec 19 hallmark law verbatim: crafted tavern goods carry the maker's hallmark and grade Proven, kits sell spectacle + breadth only, a hall fully kits reads "nice hotel" and crafters win); (4) THE DOOR THAT TRAVELS (one-click join from ambient presence, the LFG petition path; the pub is a social MODE not a standing cost -- the clock runs while held, never while you sleep). PUB LAWS: a room is a look never a number (no combat stats, no buffs, no stat gap between pubs); money never buys content the free doors do not also get (the early-entry law); tolls orthogonal; placement scopes service truth never sold; preview never debits; no free text ever. prd sec 23 THE SPONSOR STAGE (the owner's ego rite): $20 buys +5% drop AND xp FOR THE WHOLE SHARD for the owner's 40-60-minute window (exact length a build-seat number); the sponsor's name + guild + faction credited across the whole hour from SERVICE RECORD; the roll public on the website + an in-world banner; NO CUSTOM MESSAGE EVER (the owner's anti-abuse call became the no-free-text law in a sponsorship jersey -- no message slot, nothing to moderate, no report flow). STAGE LAWS: the RATE IS THE CEILING (a second $20 during a live stage EXTENDS the clock, never makes +10%; +5% authored, no purchase moves it); everyone rides equally (the free row never rides worse than the seat next to it); the COMBAT FIREWALL (duels/arena/rated rooms read base rates always, a personal stat changes by purchase NOWHERE); THE TITLE SPLIT per the owner's fairness model (the BUY route mints the suffix "the Investor", the baron's shape per sec 17; the DEED ROUTE -- a slot bought whole on earned-deed sigils, the sec 9 charter's two-way door -- mints the prefix "the Philanthropist", deed-minted only, NOBODY BUYS AN HONOR holds; a wallet buys the hour, never the prefix; a paying player earns the prefix by the same grind and gets nothing early). THE HONEST SEAM RECORDED: sec 9's no-XP law governs PERSONAL and track purchases; the stage's XP leg is the owner's authored exception for the PUBLIC shape (identical +5% for every rider, the exception runs ALONGSIDE the law and is capped to this section; no personal XP purchase exists anywhere else). IMPLEMENTATION SEATS (build rounds): the hold keyed (world, owner, slot) through the instance lifecycle + travel-board reader + furniture on the sec 19 rails; the stage clock on the shard ledger tx roots, the +5% drop leg on the SAME central roll-time modifier sec 14's charms landed on (one bucket, never bandaids), the XP leg on the gain hook (LevelCurve stays the ONE authority), one $20 SKU + a STAGE sink row, the roll page, the prefix+suffix TitleData rows. NUMBERS: investor paragraph renumbered sec 21 -> sec 24 (+ two clauses: the pub and the stage); bench now TWELVE rows. DOC-ONLY round: zero .tres, zero service changes, the pack export stands.
  > **Last updated 2026-11-05 (waystone market round):** SPITBALL #9 GREW THE OWNER'S AMENDMENT -- THE OPEN MARKET: (1) THE STONE TRAVELS -- never soulbound, the deliberate divergence from the res rails (the Soulbinder's Ticket binds to the hand that needs it; a waystone binds to its PLACE, and places pass hands); stones ride the trade window from birth (TradeService stands) and the player markets the day that seam lands. (2) THE RUNNER INDUSTRY -- the owner's living: marking stones is a VERB, not a chore; a runner crafts blanks (the alchemy bill), inscribes fresh 3/3 marks at the doors people want (dungeon mouth / harbor berth / deep-dive shelf) and sells at prices they set; the sink multiplies by design (every traded recall consumes a stone, every consumed stone sells a blank, every blank pulls reagents -- the runner IS the supply chain, nothing mints marks for free). (3) THE GAZE BEFORE THE LEAP -- the owner's anti-ripoff seat law-grade: viewing OR using a stone pops the destination BEFORE anything fires (mark name + zone + map ping to the exact spot), a destination-confirm step with no hand taken (preview never debits in its most literal dress); a recall leg without a confirm path refuses to exist; the gaze is SERVER TRUTH -- the eye sees the actual mark, never the seller's blurb (NO FREE TEXT EVER: the destination line is the inscription record, not the vendor's promise; AS-MARKED AS-GOES). (4) MARKET LAWS -- a traded stone keeps ITS mark (the mark rides the item, never the marker); a traded blank is a fresh blank (trade never mints marks); shelf price is the floor of the law, not the market's price. OPEN-SEAT ELEVATION: per-item mark storage is now LOAD-BEARING (a traded stone must carry its mark through the trade window or the runner industry cannot exist) -- interim fallback stays the fixed owner-home stone, instancing gets its own build round. Docs secs 20 unchanged in numbering; bench row untouched; DOC-ONLY round: zero .tres, zero service changes, the pack export stands.
  > **Last updated 2026-11-05 (waystone round):** SPITBALL #9 AGREED (owner pitch, Buffy yay + one canon fix): prd sec 20 THE WAYSTONE LEDGER -- UO-style recall runes landing through the res shape ("instead of res, ~3 teleports on a stone, then the stone dies"), the standing door for the ANCIENT OWNER CANON: benders were the only class that could teleport its party. THREE RAILS VERIFIED: the res shape stands (item_soulbind_ticket, stack 10, soulbound, 25-sigil sink ~$1.25, RESPAWN row family); the class family table carries the Bender row (Akkan->Seer, Human->Temporalist, Synthetic->Overclocker, role = 5); and the "benders port the party" canon line existed ONLY as institutional memory -- grep found NOTHING in any PRD or class data, so THE CANON FIX CAME FIRST, NOT THE MERCH: labs/prd.md's class table now carries the standing line -- Benders are the only class family that can teleport party members (one verb, three voices: the Seer's spatial fold, the Temporalist's slip, the Overclocker's blink), no other class teleports the party, and WAYSTONES are the no-Bender fallback door (slower, charge-bound, mark-scoped, never a replacement for the class verb). THE STONE: (1) MARK -- a blank stone kneels and inscribes (3-second channel), current standing ground written in, one place per stone, the item speaks its mark on its own card ("Waystone: the Salt Pans"); (2) RECALL -- three charges, then the stone crumbles to dust and the mark dies WITH it (no orphaned marks, the world forgets at the stone's pace); any party member may inscribe, the recall is a PARTY CALL with a 10-second consent prompt per member (never forced displacement, the honor edge), solo use legal; (3) THE PRICE, the owner's felt balance signed into law: craftable at the alchemy bench from honest reagents (the hours-farm lane) AND on the Concord shelf at 15 sigils ~$0.70 gross ~$0.50 net (the res row's sink shape, no toll -- money never mints permanence here so the sec 16 chartered shape does not apply), brewing THE WORTH-IT SCISSORS the owner named: "worth it right now? hours to forge another, but then again only $0.50" -- a sink earns its keep only when the price tugs. LAWS: convenience never power (no XP/gold/stat, the sec 9 charter family holds stone-side); the map's hold is the door (marks refuse inside dungeon/instance/warded grounds by name; a recall that would land in the sea or inside rock resolves to nearest safe ground -- the res law verbatim); consent + cooldown (the recall leg rides the QoS rate gate via the CooldownService law; recall rides the existing PlayerLockService.cancel_on_teleport chain); preview never debits (card shows charges + mark, shelf shows price, prompt shows destination). IMPLEMENTATION SEAT (build round): item_waystone rides the res-ticket .tres shape; PER-ITEM MARK STORAGE IS THE OPEN SEAT (per-slot item meta does not exist in the bag schema today -- the honest fallback is a fixed one-mark-per-character owner-home stone, instancing deferred to its own round); shelf row joins the sink rows as a new TELEPORT row under the no-fake-sinks law (the grant leg ships WITH the row or the row does not land). NUMBERS: investor paragraph renumbered sec 20 -> sec 21 (+ one clause: the waystone in the one-paragraph answer); bench now TEN rows (waystone row AGREED, canon landed). DOC-ONLY round: zero .tres, zero service changes, the pack export stands.
  > **Last updated 2026-11-05 (homestead round):** SPITBALL #8 AGREED (Buffy pitch, owner yay on ALL seats WITH AMENDMENTS): prd sec 19 THE HOMESTEAD LEDGER -- housing, the "immediate lasting value" pillar, on VERIFIED rails: DwellingService stands (plot 50k / house 750k / guard 250k / ankh 100k, all priced in GOLD; placed stations host the real CraftingService.craft gate), sec 11 already names housing furniture among its carriers, the almanac owns the world's clock; NO deed move exists in code today (grep-verified: no relocate/move legs), so THE DEED MOVE is authored fresh in this section with pricing born inside the toll law. THREE SEATS: (1) the front door, TWO DOORS ONE COTTAGE -- the deed ladder's flagship: first plot + cottage earnable FULLY FREE by deed milestones (~a month, the sec 16 week-per-tier shape); gold plot prices stay gold, real money never touches a price tag; THE CLOCK DOOR: money buys the same cottage NOW as the CHARTERED homestead, provenance-stamped, and the clock is the only thing it buys. (2) the furniture two-lane, THE HALLMARK LAW: field furniture craftable at the real stations; catalog kits sell spectacle + breadth only (sec 11 law verbatim); furniture paint rides the dye lanes, kits ride the sec 12 locker overlay; crafted furniture carries the MAKER'S HALLMARK and grades Proven by the sec 10 purse law -- catalog furniture is hallmark-less, stamps no deed-truth, and a hall wall-to-wall in kits reads "nice hotel" to any visitor: deed-made furniture is worth more and the crafter industry wins to the kits. (3) the deed museum: the deed plate (sec 18) and Ledger chapters (sec 15) get a PHYSICAL seat -- the deed bookshelf station + the front-door plate readable by visitors; a home is a resume; housing becomes the display case the earn side already earned. OWNER'S TOLL AMENDMENTS RIDDEN AS THE sec 16 CHARTERED SHAPE: (a) THE DEED MOVE -- earned cottage's FIRST move FREE, later moves flat, CHARTERED homestead +20% on EVERY move (money bought the arrival, never a cheaper road); (b) THE CHARTER'S TOLL ON SIGNATURES -- catalog signature centerpieces (the special hearth) carry ~5% luck damp while placed, riding sec 14's ONE central roll-time modifier beside the chartered tiers (tolls share the central bucket, never per-item bandaids, the spiritbind jackpot rolls identically: nothing buys the jackpot), damp visible on card + purchase flow. PLATE CROSSING: sec 18's walk-back gains ONE seat -- "Settled." the first front door landed the EARNED way (a chartered buy fires nothing: the plate reads the world, never the wallet). LAWS: furniture is a look never a number (zero stats, zero function, no home-hearth heal); placement scopes are service truth and never sold; NOBODY BUYS AN HONOR (chartered homestead mints no house name/title/plaque wording); PRICES STAY GOLD (real money touches only the clock SKU + catalog looks); preview never debits, tolls authored and visible; rarity follows the verb. NUMBERS FIX: the deed plate landed last round as sec 18...19? NO -- it landed as sec 19 and FORCED investor to sec 20, leaving a sec 18 HOLE (17 -> 19). Fixed by renumbering: deed plate 19 -> 18, homestead seats in as sec 19, investor STAYS sec 20 (its one-paragraph answer grew the homestead clause: earned front door, move-toll + signature toll, breadth under the hallmark law); bench now NINE rows (deed-plate row home corrected 19 -> 18). Implementation seat: clock-door SKU + kit SKUs ride the webhook-provider seam, sink rows carry toll fields, the deed move rides DwellingService as a relocation command reading the ledger's deed/bought stamps for FREE/+20%, hallmark fields on furniture cards, bookshelf + door plate read the SAME ledger through the deed plate's readers. DOC-ONLY round: zero .tres, zero service changes, the pack export stands.
  > **Last updated 2026-11-05 (deed plate round):** SPITBALL #7 AGREED (owner pitch, Buffy yay): ACHIEVEMENTS ALONGSIDE THE PRD -- the owner nailed the marquee ("the Chosen is def achievement territory -- get your first Spiritbound item"). prd sec 19 THE DEED PLATE: not a new economy, the EARN SIDE made visible. Verified the rails before writing: the AchievementData schema CARRIES the whole plate already (Rarity tiers, title_reward, hidden + secret_description for mystery plates, a meta-ACHIEVEMENT category with required_achievements chains; GLOBAL/PROGRESS/COLLECTIBLE types; 32 authored .tres riding AchievementService + achievement_listeners + AchievementUI + toasts) and prd-quests.md's canon law holds ("achievements celebrate the world's verbs, not grind counters -- never collect 10,000 herbs"). THE WALK-BACK: sec 14 "the First Landing" (FIRST spiritbound item -- hidden until landed, legendary by construction, and the Chosen prefix mints from the SAME trigger: one fact read twice), "the Fated Find" (fated stamp; the find celebrated, the charm never), sec 10 "Proven" (a Mythos exclusive graded Proven -- the purse grade as trophy), sec 9 "the Earnest One" (a Charter bought WHOLLY on 300 earned-deed sigils -- the one purchase-adjacent seat and it is still a deed story), sec 11 "Full Spectrum", sec 12 "Handled", sec 13 "the Standard Bearer", sec 15 "Named on a Page", sec 16 "Expeditioneer" (PROGRESS chain mirrors the four deed tiers; chartered shows nothing), sec 17 "the Full Rope" (required_achievements chain over the rope's prefixes). PLATE LAWS: the plate reads the world never the wallet (no achievement fires on a purchase act); verbs never grinders (canon law verbatim); ONE DERIVATION THREE READERS (the trigger fact read by the sec 17 title mint, the sec 15 Ledger chapter and the plate -- never a parallel counter; the honesty-law pattern's third dress); every plate free by construction (money never lifts/skips/buys progress, the jackpot law plate-wide); rarity follows the verb; NO NEW FIELDS (mystery = hidden + secret_description; trophy titles = title_reward resolving to the SAME authored TitleData the ropes mint). Investor paragraph renumbered to sec 20 (+ one clause: the plate in the one-paragraph answer); bench now EIGHT rows. DOC-ONLY round: zero .tres, zero service changes, the pack export stands.  > **Last updated 2026-11-05 (Chosen rename round):** SPITBALL #6b's ROPE CROWN RENAMED: "the Spiritbound" prefix is now "THE CHOSEN" (owner asked Gifted-or-Chosen; Buffy chose Chosen). WHY: "the Gifted" collides with gift/economy vocabulary (a title that reads as a transaction is what sec 17 bans by law) and "the Spiritbound" was borrowing sec 14's MECHANIC name for the person's plate -- "the Chosen" points the title at the person (chosen by luck, never bought) while the spiritbound stamp stays in the item-card lane where it was always king. Line-edited the single PRD mention (sec 17 walk-back crown + the unbuyable-by-construction law kept verbatim); sec 14's mechanic law line untouched. DOC-ONLY round: zero .tres, zero service changes, the pack export stands.  > **Last updated 2026-11-05 (expedition + titles round):** SPITBALLS #6 AND #6b AGREED (owner pitch, Buffy yay with two sharpenings). prd sec 16 THE EXPEDITION PACK -- four permanent tiers (Expedition I-IV) growing the bag (InventoryComponent.expand_inventory/MAX_BAGS), the bank (expand_bank/MAX_BANK_EXPANSIONS) and the GUILD_VAULT container family (sec 13), +12 slots/tier riding the container schema's own SLOTS_PER_TIER rail. F2P LEG: every tier deed-earnable in roughly a week (quest milestones, ledger appearances, heraldry deeds), the full ladder ~a month free; MONEY SKIPS the ladder (the clock law) but bought tiers are CHARTERED: provenance-stamped in the account ledger and carrying THE CHARTER'S TOLL, a small authored luck damp (~5%) riding sec 14's one central roll-time modifier while chartered tiers are held -- identical capacity, but the chartered hold never grades Proven and mints NO title (the honor difference IS part of the authored tradeoff). LAWS: capacity is never a stat; money buys the clock never the ceiling; the toll is authored and visible on the purchase flow; the guild-vault leg seats on sec 13 (rank-gated, vault-bought, mix tracked); preview never debits, purchases permanent, no Charter gate. prd sec 17 THE TITLE ROPES -- the walk-back over the pre-existing rails (TitleData prefix_form/suffix_form + Category/Rarity/UnlockMethod incl PURCHASE; TitleService unlocked/equipped_prefix/equipped_suffix/title_color/title_unlocked; PURCHASE precedent title_deepseabaron.tres via sigil_sink): titles need POLICY, not a system. ROPE LAWS: a title is a look never a number; NOBODY BUYS AN HONOR -- prefix form is deed-minted ONLY, sales mint suffixes at most (the baron's shape); rarity follows the deed not the wallet; no free text ever; toll orthogonal. THE WALK-BACK: dye-Dyer (sec 11), Wardbearer (sec 12), Herald of Guild (sec 13), the Fated PREFIX for a bought-charm rare find + the SPIRITBOUND prefix for a jackpot landing (sec 14 -- unbuyable by construction, which is what makes the prefix law mean), Chronicler (sec 15), Expedition I-IV prefixes deed-tier only (sec 16). Investor paragraph renumbered to sec 18 (+ one clause: the storage ladder in the one-paragraph answer); bench now SEVEN rows. DOC-ONLY round: zero .tres, zero service changes, the pack export stands.  > **Last updated 2026-11-05 (almanac carrier round):** SPITBALL #5 GREW ITS CARRIER (owner's append): the Whisper Ledger's news does NOT build new furniture -- it prints on the SKY ALMANAC (SkyAlmanacUI, the page the moon and sailing reads already share) at the same almanac-day cadence the world's weather calendar already marches to; the almanac being the world's memory (the mystery_data law), the Ledger writes INTO that memory instead of a parallel book. THREE CARRIER LAWS: (1) ONE DERIVATION, TWO READERS -- the whisper page derives from the same central drop/landing facts the town herald's voice reads, never a second copy (the honesty-law pattern the almanac already runs: ferry chart and dock cannot disagree, the bug lives in one file); the chart in the page and the whisper in the village are one record. (2) NOTABLE LANDINGS BECOME CHRONICLE -- a recorded landing files as an Acts-style chapter (index, source_name "The Ledger", record_text the template line, gate_day the landing's almanac day), so the mill's news persists with the world's memory beside the door records, and the page prints yesterday's rumors as history, not chat ("the day a spade lands spiritbound is a day with a page number"). (3) THE WALKED-NEWS vs SAME-DAY FORK RESOLVES BY THE SPLIT -- a Peal rings LIVE in the moment (bell in-zone, lantern burst: immediacy is the amplifier's own product), while the free whisper prints at the almanac's dawn roll (the page is the delayed newspaper, editorial voice intact): both seats get the timing that suits them from the carrier's own clock, no schedule left to invent. Implementation seat updated: whisper page in SkyAlmanacUI beside moon/sail pages (registry rows + page reader, no new UI scaffolding), the chapter leg riding the existing Acts/chronicle record rails, Peal permit .tres + sink row + zone cosmetic event, gift leg on the sec 13 vault rail; the herald line stays a thin voice-reader of the same record. DOC-ONLY round: zero .tres, zero service changes, the pack export stands.  > **Last updated 2026-11-05 (whisper ledger round):** SPITBALL #5 AGREED (Buffy pitch, owner yay "hell yeah"), the monetization of BEING SEEN. prd-monetization.md sec 15 THE WHISPER LEDGER -- the rumor mill and the Peal -- giving sec 14's spiritbind jackpot its mouth. SEAT 1, THE RUMOR MILL (free, worldbuilding first): every spiritbind landing whispers through the village heralds' evening news ("The Ledger reports a spade found spiritbound near the pans -- unnamed"); too rare for spam, the mill becomes a world clock players check like weather, advertising the luck economy shard-wide, and everyone reads free. SEAT 2, THE PEAL (the paid leg): the landing always rumors free (item + place, name withheld); the Peal PERMIT (deed-earned OR bought, the colorist license's permit shape, never Charter-gated) adds the celebration a finder rings over their own legend -- zone-wide bell, sky-lantern burst, the name carried in the rumor line instead of "unnamed"; the LANDING is never sold, only its echo. GIFT LEG: a friend or the guild vault (sec 13 rail) can buy a Peal FOR a finder -- celebrations given, not only owned. LAWS: nobody buys the landing (money never raises jackpot odds; the Peal is an amplifier, never a vendor); NO FREE TEXT EVER (rumor lines are authored template sentences filled from item-card truth -- moderation is just the withhold switch, no report flow needed); the location leg comes free ("by the drowned pier" -- a tourism engine); Charter never gates; toll orthogonal and the mill reads provenance without grading. IMPLEMENTATION SEAT (build round): the Ledger subscribing to the central drop event (the sec 14 roll-time point), a scheduled herald broadcast seat (the harbor-lights class or a world-channel line through the chat fabric), the Peal permit .tres + sink row + zone-wide cosmetic event, the gift leg on the vault rail. OPEN QUESTION: evening news as a walked schedule (honest editorial lag) or same-day whispers (immediate froth)? Investor paragraph renumbered to sec 16; bench now FIVE rows (dyes/locker/heraldry/lucky/whisper ledger). DOC-ONLY round: zero .tres, zero service changes, the pack export stands.  > **Last updated 2026-11-05 (spiritbind jackpot round):** LUCKY GREW A GLOBAL JACKPOT (owner's second append, same spitball #4, prd sec 14): beyond the fated stamp on bought-luck finds, EVERY drop in the world -- a wild stick, a market roll, an earned mythic, a crafting output -- rolls the same TINY AUTHORED global chance to land SPIRITBOUND, the world's rarest binder; luck of the draw on a stick or a mythic alike, item card is the only herald. LAWS: (a) the jackpot lives in the SAME central roll-time modifier as the Lucky charm, one global spiritbind leg, never per-item; NON-STACKABLE GEAR ONLY (stackable materials vetoed -- a bound stack is junk-locked); (b) spiritbound is PERMANENT and honest, item card forever; it is the rarest PROVENANCE, its own prestige, not a punishment tier; (c) MONEY NEVER TOUCHES THE JACKPOT ODDS -- a bought charm lifts only the charm's drop rate; the spiritbind leg rolls identically under bought, deed, and no luck alike; nobody can buy the rarest binder, which is exactly the froth; (d) toll orthogonal -- the jackpot lands ON TOP of whatever the purse already stamped, Mythos grades untouched; (e) free-path by construction -- the jackpot rolls whether or not Lucky exists in the market; Lucky and plain grinding both just widen the number of rolls a player makes. DOC-ONLY round: zero .tres, zero service changes, the pack export stands.  > **Last updated 2026-11-05 (spitball lucky round):** SPITBALL #4 AGREED WITH TWO CUTS. prd-monetization.md sec 14 LUCKY -- the weekly luck pot. The owner's shape stands: 24-hour charms, affordable-to-grinders ≈$1.25 gross (the Soulbinder ticket's 25-sigil price shape), luck across the WHOLE economy (kill drops, the black-market roll board, premium rares) rather than one gear chain. THE POT LAW (Buffy's reframe): every account owns a 7-luck-day weekly pot, all days at the same potency; days 1-2 are earned nearly free via deeds (the owner's earn rule, so normal/moderate play lucks 2), days 3-7 are bought at 25 sigils per 24-hour charm -- money buys the CLOCK (skips the deeds), never more luck than the ceiling every account has; pot resets on the world's weekly tick, the charm runs 24h from ACTIVATION, not purchase. CUT (1) NO XP LEG: luck raises drop odds only, never XP gain or gold-per-kill -- sec 9's no-XP law does not bend for $1.25. CUT (2) THE AUTHORED TRADEOFF, which the stat-only law required: rare finds under a BOUGHT charm come out FATED (bind-on-luck, soulbound, item card says so); finds under a DEED day trade free -- money cannot mint tradable wealth at scale and deed luck stays strictly better (the earned-is-worth-more tenet applied to fortune itself). LAWS: ONE central roll-time modifier over the drop sources (never per-item bandaids), the pot UI preshows remaining days before purchase (preview-never-debits in its cheapest dress), no refund once a day's 24 hours start, the pot lives on the account ledger via the tx roots with each day stamped deed/bought (provenance reused), toll orthogonal and never Charter-required. IMPLEMENTATION SEAT (build round): weekly pot meter in the account ledger, the consumable charm .tres + the sink row, the central drop-modifier point, the fated stamp on lucky-found premium rares, the pot UI. OPEN QUESTION: does Lucky lift harvest-node yields too or only kill/roll drops? (harvest-skip is the shape that starts to smell). Numbering note: the investor paragraph is now sec 15 (renumbered twice this round: 14 -> provisional 16 -> corrected 15; bench now FOUR rows: dyes/locker/heraldry/lucky). DOC-ONLY round: zero .tres, zero service changes, the pack export stands.  > **Last updated 2026-11-05 (spitball bench round 2):** SPITBALLS #2 AND #3 AGREED AND DESIGNED, the investor paragraph renumbered to sec 14, and the bench table now carries three rows. (1) THE WARDROBE LOCKER (sec 12, spitball #2): one per-account unlock carries any OWNED cosmetic look across any OWNED carrier -- and it RIDES THE OWNER'S CROSS-ACCOUNT TX ROOTS per the owner's seat call: a look's unlock persists as ledger lines in the same account-scoped transaction family (not item copies surviving inventory moves), deed-earned looks keep their sec 10 grade and nothing strengthens by passing through. FREE LANE: field-crafted looks always locker-eligible in a small slot set; premium grows the slot count, never look access. LAWS: a look is never a stat (no stat smuggle, no expensive-tier card on a cheap carrier), Charter never required to use the locker on an owned look, preview never debits, toll orthogonal. Implementation rides sec 11's wardrobe-overlay decision -- looks and dyes get ONE surface patch. (2) GUILD HERALDRY PACKS (sec 13, spitball #3): crews buy kits of the guild's OWN marks (emblem + colors + motto) as looks on the visible surface itself (hall banners, barque-sail flags, house plaques, member trims) -- the price scales by the group and groups churn less. PURCHASE SHAPE: bought FROM a guild vault any member can deposit into, the vault tracking its own earned-vs-bought mix per the sec 10 purse law (an earned crew buys wholly on deed sigils), rank-gated buy permit, no member forced online for the unlock. LAWS: heraldry is a look never a buff, hateful/misleading marks ship with report + takedown from the first build round, every guild earns ONE standard-emblem banner free at creation (Concord kits widen the look range, never gate the badge), kits never graded and never Charter-required. Implementation: guild ledger with double-entry deposit + kit-purchase tx legs, and the same overlay seat. DOC-ONLY round: zero .tres, zero service changes, the pack export stands.  > **Last updated 2026-11-05 (spitball dye round):** THE FIRST SPITBALL LANDED AS DESIGN. prd-monetization.md sec 11 THE DYE ECONOMY: one dye slot over many carriers (weapons/armors/wearables/accessories/mount tack/gliders/housing furniture); a dye is a LOOK, never a number. TWO-LANE COLOR LAW: field dyes are craftable from harvests (free lane, honest mundane coverage, a vendor-shelf trade good a crafter can run as an industry) and premium sells SPECTACLE + BREADTH ONLY (iridescent/animated/seasonal Concord dyes + camo patterns) -- never exclusivity of a field-reachable look. The colorist's license (custom full-spectrum chooser) prices as a reusable PERMIT, the ticket shape. LAWS: preview never debits, failed applies refund, dyes ride the Charter without requiring it, the Toll stays orthogonal. THE SPITBALL BENCH table now lives at the section's foot (one row per agreed idea -- the standing workflow: owner starts, Buffy lands after yay). DOC-ONLY round: zero .tres, zero service changes, the pack export stands.  > **Last updated 2026-11-05 (pass design round):** THE PASS AND THE PREMIUM POWER LADDER GOT DESIGN, NOT VIBES. (1) THE SEASON CHARTER (prd-monetization.md sec 9): one purchase per season, never a subscription; premium track is cosmetics + non-combat convenience ONLY (mount SKINS skin owned rides, early entry is time not power); HARD LAWS -- no combat stats, no XP boosts, no debuffs on others, no content the free game won't eventually get; the F2P door is TWO-WAY: a free track (dye kit, trophy, convenience tab) deeds-only for everyone, AND the Charter itself purchasable $8.99 OR 300 EARNED-ONLY sigils from the deed pool alone. (2) THE MYTHOS TOLL (sec 10): paid exclusives carry an authored, item-card-visible tradeoff from the coverable-hook set (move/resist/regen/haste, never damage/health/defense), graded by wallet provenance -- the purse stamps each sigil bought (webhook) or deed (earned in-world), Mythos debits strike DEED sigils first, and the toll grades Proven (100% deeds, NO toll) / Tempered (>=75%, halved) / Bought (<75%, full): the grinder's mythic exclusive is strictly BETTER than the buyer's; money buys the clock, never the ceiling. (3) IMPLEMENTATION SEAT: earned sub-ledger, sink rows with toll fields, the catalog receipt's provenance legs; RMT hazard flagged (deed sigils bind-on-earn the day trading opens). DOC-ONLY round: zero .tres, zero service changes, the pack export stands.  > **Last updated 2026-11-05 (funding pitstop round):** THE MONETIZATION FLOOR GOT ITS DOCUMENT. labs/prd-monetization.md now stands as the standing model: what ships (three real-$ SKUs $4.99-$24.99 riding the webhook provider seam, the 9-row audited sink catalog where the res ticket = ~$1.00 net, the mount ladder $7.50-$45, cosmetic titles, the 3/12-sigil black-market roll board, and the in-world earn path), what servers cost at scale (Tier 0 pilot ~EURO 30, Tier 1 launch ~EURO 250, Tier 2 at 10k CCU ~$2.8-4.2k, i.e. ~$0.35/CCU-month and ~$0.04/DAU-month, with 2026 publisher-page anchors), and what the gap requires. BREAK-EVEN HEADLINE: ~2,000 monthly payers cover the entire at-scale infrastructure budget. Risk #1 (PvP x soulbind tickets) recorded as the catalog's largest open design decision; per-shard CCU benchmark and provider adapters recorded as the model's next hardware and code legs respectively. This is a DOC-ONLY round: zero .tres, zero service changes, the pack export stands.  > **Last updated 2026-11-05 (ladder round):** THE FIRST RUN HAS ITS OWN LADDER -- every 5 levels a few types, biome-matched, honest to the curve. (1) 14 ENEMY TEMPLATES: Meadowhaven L5 (field_hopper + tusker_sow), the gloomwood L10/15 (thistle_boar + gloam_whisp_moth), the pans L20/25 (salt_wretch + mirage_hound), gull island L25/30 (coast_pecker + nestmaw ELITE), root camp L30 (rootmaw_brute ELITE), the depths L40/45/57 (gloam_polyp / depths_thornhide / ledgewarden_construct ELITE -- the band-57 gap filled), the sea L55/60 (drowned_custodian / tidebound_ancient ELITE). (2) THE LADDER LAW: regulars pay ~0.8% of next-level cost at parity through band 30 (the shipped slope) and the band-40+ 3% seasonal law (3000/3250/4600/4800/5500); gold and difficulty walk with band. (3) FIVE BIOME LOOT TABLES (meadow litter / gloam litter / pan dust / coast bounty / gloam spores) with the deep grades riding elite ore secondary at 30+. (4) THE FIXER: item_soulbind_ticket rides is_quest_item = true -- the zero/zero carve-out the purse law has had since birth (a never-vendored permit is quest-classed). GATES: naming 26/0, catalog 10/0, curve 15/0, canon bosses ALL PASS, schedule 37/0, lint 37/0. NEXT DUE: placing the ladder in-world (zone spawn rung), Fenwick repairs, star-tier talent lines, the first breathing-band zone.  > **Last updated 2026-11-05 (soulbinder round):** PREMIUM RESURRECTION LANDED ON THE AUDITED BOOKS -- self + the party lifeline. (1) THE PERMIT: `item_soulbind_ticket.tres` (stack 10, soulbound, zero/zero purse; never vendored -- the Concord sink ledger gate is its only door, the bag use-door refuses it as an honest inert permit). (2) THE SINK: `SinkKind.RESPAWN` + two rows (ticket x1 @ 25 sigils, x8 @ 150); the no-fake-sinks law held -- the bag-stamp grant leg shipped with the rows (InventoryComponent.add_item, all-or-nothing, per-slot dupes); RESPAWN rows are stackable permits, NO ALREADY-OWNED gate; the catalog receipt grew legs (9 rows, permit truth, repeat buys, a full-bag third refund leg). (3) THE STAND-UP: RespawnService's SELF_REVIVE seat has its cycle now -- availability rides the bag's stack truth, the 'soulbind' death-screen choice maps in, initiate_respawn is DEBIT BEFORE GRANT (one ticket out before the cycle schedules; a refused consume refuses by name), 3 s delay at the death spot EXCEPT sea/rock: `_spot_refuses_a_stand_up` (injectable `_depth_resolver` seam, runtime rides OceanService.sample_depth) sends a drowned or inside-the-rock fall to the zone spawn. (4) THE LIFELINE: start_revival's clergy gate has a paid bypass -- a ticket holder pays a non-clergy lifeline at a fallen ally, consumed AT THE BOOK (after range/target/abuse gates), audit-logged. (5) THE ROW: the death screen offers 'Soulbind at the Fall (Ticket xN)' + a11y price line; a stale UI signal stays free (server re-validates + consumes). Real-$ entry rides the existing processor SKUs -- zero new payment code. GATES: soulbind 30/0 (joins DEFAULT_SET), sink catalog ALL-OK (9-row extension), premium loop ALL-OK, lint 37/0; DEFAULT_SET 116. NEXT DUE: the enemy ladder every 5 levels to 60, the band-57 gap, Fenwick repairs, star-tier talent lines, the first breathing-band zone.  > **Last updated 2026-11-05 (income round):** THE FIRST SEASONAL PACK PAID THE CURVE. (1) THE INCOME LAW lands as pack-authoring precedent: BAND REGULARS PAY ~3% OF THE NEXT LEVEL'S COST AT PARITY, so the breathing band grinds at MMO-normal arithmetic and follows the curve wherever a seasonal cap moves it -- the packs author income, never the curve file. (2) TWO BAND REGULARS: `enemy_tidecursed_diver.tres` (band-40, the sea keeps what the squeeze line kept; primary loot_sunken_salvage + elite ore secondary) and `enemy_gloamwood_stalker.tres` (band-50 ELITE, the Gloomwood's digger; elite ore secondary -- the deep grades in its gullet). (3) FOUR PAYING QUESTS: Fenwick's chain `quest_tide_salvage` (The Tide's Tithe, min 38, diver kill + kelp haul) -> `quest_sentinel_wake` (The Sentinel's Toll, min 42, KILL the Trench Sentinel -- rides the boss's own 4h cadence, starmetal freight) -> `quest_gloamwood_ledger` (The Gloamwood Ledger, min 48, stalker clearing, mythril freight); and Marsh Piper's deep DAILY `quest_deep_toll` (The Market Toll, min 35, 3 abyss pearls, repeatable). Giver seats: Fenwick carries the chain, the jeweler carries the toll. (4) GATES: naming 26/0, catalog 10/0, availability 15/0, curve 15/0, lint 37/0; gen_icons 147 referenced / 4 mints / 0 residue. NEXT DUE: a band-57 regular for the 55-to-60 gap, the Fenwick tide-side repair service, the star-tier accessory talent lines, and the first breathing-band zone (the Tithe's six barque decks).  > **Last updated 2026-11-05 (cap-lifting round):** THE PROGRESSION RATIO LAW LANDED AND THE TRENCH SENTINEL HAULS IT OUT. (1) THE RATIO SYSTEM -- `game/core/progression/level_curve.gd` is now the ONE AUTHORITATIVE LAW: the player level cap is DEFAULT_CAP=60 (seasonal packs bump this ONE constant; junk or absurd LEVEL_CAP falls back to 60, never a boot failure), the 1..10 shipped 1.5^n tutorial band stays byte-equal, and levels past the band breathe as band_top x 1.03^(l-BAND) so the curve compounds gently instead of the old geometric explosion; PlayerManager consults the curve (level-up stops at LevelCurve.max_level(), next-level cost from the curve, overflow XP banks instead of vanishing). (2) THE SWEEP: 4 zones (30s and under to 999), 4 content-band quests (to 100), and 1 gateway (50->100); the FIVE tutorial gates stay verbatim (main*5, arena8, wolves10, wings12) as walk order, never caps. (3) THE DRIFT RAIL: the new test_level_curve receipt (15/0) joins DEFAULT_SET and its data law now REFUSES any zone/quest/gateway max_level value that re-bakes an absolute content ceiling -- the exact mechanism that led people and authors to think the world ended at level 30. (4) THE TRENCH SENTINEL: enemy_trench_sentinel (band-45 WORLD_BOSS) + world_boss_trench_sentinel (zone_sundered_sea, every 4h after 10 min boot delay, 1h unclaimed sweep) + loot_trench_dream (sigil .10 / starmetal .30 / mythril .35 / abyss pearls 2-4 @ .60) and the Sigil itself acc_necklace_pearl_sigil as the signature drop: +10m squeeze grace, current-immune, wis 7 vit 4 -- the trench boss writes the NEXT LEVEL of the squeeze line, not a bigger number. Fenwick already buys the raw haul via buy_categories [3,4] and the Jeweler already buys pearls -- the sentinel round rides those rails untouched. GATES: level curve 15/0, item catalog 10/0 (sigil minted; 143 icon refs / 1 mints / 0 residue), naming 26/0, canon bosses ALL PASS, world-boss schedule 37/0 (pre-existing suite artifact differential-verified) and lint 37/0. NEXT DUE: the real first band-40/50/60 seasonal pack pays the curve (quests/enemies), the Fenwick tide-side repair service and the star-tier accessory talent lines.
  > **Last updated 2026-11-05 (shore plankwright round):** FENWICK'S FENCE & PLANK GAVE THE SHORE ITS SECOND STALL, AND THE DEEP TAXES NOW HAVE A SKIPPER TO HAUL FOR. (1) THREE .tres, LAWFUL SHAPES ONLY: `npc_tidewright_fenwick.tres` (Old Fenwick, merchant npc_type 6, zone_village_center, merchant_general scene reused, jeweler-template voice) + `vendor_fenwick_planks.tres` (by_item_id: res_timber x16 / item_scrap_lumber x10 / wep_longbow x1 -- the Shorebow he strings once a season; buy_categories [3,4] so the yard pays for provisions and raw haul; honest row stock, daily restock) + `tidewright_fenwick_intro.tres` (5-node tree: tar bucket, six barque-deck rebuilds, both moor banks his joinery, warped-billet refusal, kelp-wrap draw advice; two shop-open legs ride action_type 6). (2) SEATS: zone roster row appended (5 village npcs) + globe seat at bearing 135 / reach 0.012 in VILLAGE_NPC_BATCH (the open arc between the jeweler's 110 and the academy's 160). (3) IN PASSING CONFIRMED the pearl chain is REACHABLE IN-WORLD: trench pearls live at 50-58 m and reef kelp at 30-45 m as live HarvestService nodes (six authored beds, respawn 900/420 s), bands refuse too_shallow/too_deep, the jeweler's shelf also stalls raw pearls -- the dive and the daily both genuinely complete. (4) GATES: catalog 10/0 (include + vendor-stock laws over the new shelf), naming 26/0, lint 37/0. No new icons (the shelf re-rides minted paths). NEXT DUE: star-tier accessory talent lines; a tide-side repair service for the tidewright; the post-Phase-2 cross-shard event quest note.
  > **Last updated 2026-11-05 (pearl industry quest round):** THE JEWELER'S OFFER BECAME A ROAD: HER BENCH DIALOGUE'S PROMISE IS NOW TWO CHAINED QUESTS. (1) TWO QuestData .tres, LAWFUL SEAMS ONLY (zero service changes): `quest_pearl_dive.tres` "A Pearl for the Piper" -- COLLECT "Abyss Pearl" x2 (the COLLECT bridge credits by item display_name) + TALK npc_jeweler_haven, min_level 8 (the abyss breather's own gate: nobody honestly dives the 50-58 m trench bands without it), zone_restriction zone_village_center, rewards 250/400 gold/xp + acc_ring_tidecaller chance 1.0 (the jeweler pays the dive off her own shelf). `quest_tideline_kelp.tres` "Tideline Gather" is the bench's DAILY (quest_type 2, is_repeatable, cooldown 86400): COLLECT "Kelp Fiber" x6, chain law both directions (previous_quest_id + the dive's next_quest_id), rewards 80/120 + tea_mooncap_steep x2 dive rations. (2) RECEIPT: test_quest_availability.gd extended IN PLACE (no fleet-pack regen, DEFAULT_SET unchanged): at level 12 the dive lists while the kelp daily stays chain-locked; after the dive reads REWARDED the chain gate opens and the daily joins the roster. (3) ICON LAW MINTED ITS OWN: res://icons/quests/{pearl_dive,tideline}.png exist on disk (gen_icons.py 142 referenced / 2 mints / 0 residue). GATES: availability receipt exit 0 (15 OK), catalog 10/0, naming 26/0, lint 37/0. NEXT DUE: the deferred shore fence/bridge vendor pairing (data + shelf + globe seat), star-tier accessory talent lines; OpenHands owns core/mesh Phase 2, so this round stayed data-only.
  > **Last updated 2026-11-05 (jeweler world-spawn fix + live-client round):** THE MANUAL CLIENT TEST CAUGHT WHAT THE RECEIPTS COULD NOT: THE JEWELER HAD DATA BUT NO WORLD SEAT. (1) THE CATCH: the new web-client path (repo shell `web/` served by the vite dev server at /game/) was given a FRESH staging pack (`--export-pack Web` from this worktree; template-free, hash re-stamped like web-ci) and booted end to end: lander -> guest login (`Single-machine mode`) -> character lobby -> species/class pick -> globe world boot with HUD, weather, and rosters. THE JEWELER DID NOT STAND THERE: boot log said "town rosters placed (6 village, 9 capitol)" and the boot roster named six village NPCs -- the zone .tres roster row that the jeweler round added drives PLANAR-zone placement only, while the GLOBE (the primary playable world) places town NPCs from the hard seats in globe_world.gd. (2) THE FIX: npc_jeweler_haven joined VILLAGE_NPC_BATCH at bearing 110 / reach 0.012 (an open lane between the smithy's 44 and the academy's 160, the owner's "all the NPCs in the starter village" law), so the pearl-cutter now has a seat in the world, not just a card in the catalog. Gates: lint 37/0 (run with GODOT pointed at the local binary; the suite's default /tmp godot is a stale path and must not be trusted for a red) DEFERRED: the in-browser walk-to-NPC + shop-open leg of the manual session (terrain derive saturates the 2-core VM mid-session; the boot leg is verified)
  > **Last updated 2026-11-05 (shard-mesh Phase 1 round):** THE CROSS-SHARD BUS LANDED, AND THE MESH STOPPED TALKING TO ITSELF. Phase 0 made shards distinct; Phase 1 gives the coordinator's cross-shard events a REAL transport. `game/core/mesh/` is a swappable seam (the payment-provider plugin law): `shard_bus.gd` is the contract (`subscribe`/`publish`/`poll`) with the MAILBOX PROTOCOL -- each bus instance has a self id (its shard id), `publish(topic, message)` drops a JSON copy into the per-(subscriber, topic) inbox list of every OTHER subscriber (THE NO-ECHO LAW: a publisher never receives its own fan-out), `poll(topic)` drains the self inbox; per-topic inboxes mean one shard can subscribe to several topics without stealing another's mail. `shard_bus_registry.gd` is the plugin board (re-registering an id REPLACES the bus = the swap law; `make_default` re-points), seeded with `memory_shard_bus.gd` (the process-local default; a shared static store so two in-process shards exchange events) so dev/CI are unchanged; `redis_shard_bus.gd` is the cross-process transport over the redis-bridge sidecar. THE COORDINATOR WIRING: `CoordinatorService` binds the bus (deferred past autoload order -- CoordinatorService loads BEFORE ShardManager, so a synchronous bind would always read "shard_1"), publishes on every `emit_cross_shard_event`, and `get_pending_events` DRAINS remote mail into the pending queue first, so remote events ride the same exactly-once path the tick already consumes (`_pull_cross_shard_events`). Transport selection is `SHARD_BUS_BACKEND`, defaulting to follow `CACHE_BACKEND`; a failed Redis connect falls back to the memory bus rather than failing the boot. DRIVE-BY FIX (exposed by the honest fallback): `redis_store.gd::_blocking_get` typed `_retry_request(...).data` as `Dictionary`, so an unreachable bridge raised "assign Nil to Dictionary" on the exact path Phase 1 makes real -- now `Variant` + `is Dictionary` guard. Receipt `tests/test_shard_bus.gd` exit 0 seventeen legs (registry default, swap law, memory round-trip + no-echo, cross-instance coordinator delivery + local retention, env fallback, honest redis failure). Gates: shard bus 17/0, Phase 0 receipts still green (identity 12/0, adapter HTTP 5/0), tick phase2 24/0, data-naming 26/0, lint suite 37/0, adapter suite 10 files rc=0, redis-bridge 20/0. Full runner NOT run (owner instruction; being reworked). Design note `labs/prd-shard-mesh.md` Phase 1 section + acceptance updated; `DEVCODE.md` documents `SHARD_BUS_BACKEND`.

  > **Last updated 2026-11-05 (jeweler shelf round):** THE JEWELRY LEARNED A DOORWAY: ITS OWN NPC SHELF ON THE JEWELRY LADDER, THE PEARL INDUSTRY HAS A FACE. (1) THE JEWELER (data/npc/npc_jeweler_haven.tres -- Marsh Piper, the shore's pearl-cutter): npc_type 6 (merchant) in zone_village_center (roster row added), merchant_general scene reused per the scene law (habits: no new tscn this round), priced in the haven-pearls-vs-sigil-gold voice. Includes: the offering shelf + a 5-node intro dialogue (jeweler_haven_intro, npc_id matched so the TALK/npc-id lint stays lawful). (2) THE BENCH (data/npc_offerings/vendor_haven_jewelry.tres, by_item_id): the FOUR jewelry SKUs ride honest row stock (tidecaller 5 / golden signet 3 / paleshard 2 / starbinder 1 -- the queen of the line is also its rarest row), plus acc_breather_abyss_pearl (3) so the ocean's gear has a shore gate, and res_abyss_pearl (8) so the trench dive has a buyer on the surface too. buy_categories [2, 4] = ACCESSORY + RESOURCE (the category enum's true order: 0 weapon 1 armor 2 accessory 3 consumable 4 resource -- verified in item.gd before wiring), so Marsh Piper pays for the pearl and takes back the jewelry you outgrew. LIMITED stock 5, daily restock. (3) THE MERGE CARRIED: OpenHands PR #51 (shard mesh Phase 0: ShardManager env identity, the DictStore/CacheWrapper static-hook shared-state fix + the --script false-green principalColumn fix, pg/redis HTTPClient transport + bridges, docker/compose/entrypoint shard wiring) landed through staging per the staging-branch law -- the GitHub merge API refuses draft PRs, so it was verified locally in this worktree (shard identity 12/0, adapter HTTP 5/0, naming 26/0, lint exit 0, catalog 10/0, both bridge suites OK: 18 + 20) and merged --no-ff on 5bc100ef as staging merge commit 936c2924; GitHub reconciled the pushed tip and records the PR as MERGED. GATES: catalog 10/0 (the six SKUs resolve, priced, stock lawfully; dialogue ref + zone roster row linted), naming 26/0, lint suite exit 0. DEFERRED: gems (still no cutting inputs -- the delisted idea stays delisted), a second shore NPC pairing (fence/bridge vendor), and the star-tier accessory talent lines.
  > **Last updated 2026-11-04 (shard-mesh Phase 0 verification round):** THE SHARED-STATE BUG HAD A THIRD LEG, AND THE RECEIPT WAS A FALSE GREEN UNTIL IT WAS CLOSED. Re-verifying the Phase 0 claim against a REAL `STORAGE_BACKEND=postgres` boot (fresh DB `synmergia_fresh`, pg-bridge sidecar) surfaced that the prior round's fix was incomplete: `BackendFactory.boot_defaults` DOES set the `DictStore`/`CacheWrapper` static hook -- but a `--script` receipt that `load()`s `dict_store.gd` can resolve a DIFFERENT script instance whose static is still null (the autoload's `preload` and the receipt's `load` desync), so the receipt's DictStore silently fell through to a process-local MEMORY fallback and the "round-trips through the registered store" leg passed against memory, not Postgres (verified: the write never appeared in the `kv` table). FIX: `DictStore._resolve_registry()` / `CacheWrapper._resolve_registry()` now fall back to the LIVE `AdapterRegistry` autoload in the tree (`Engine.get_main_loop() is SceneTree` -> `root.get_node_or_null("AdapterRegistry")`) when the static hook is unset, making resolution instance-independent. THE ACCEPTANCE CRITERION IS NOW GENUINELY MET: two separate processes (write then read) both resolve `res://adapters/persistence/postgres_store.gd`, and the second reads back `{"n":7,"shard":"shard_2"}` from the real DB; the shard-mesh receipt's key lands in Postgres too. The earlier pg-bridge fixes stand (autocommit + explicit BEGIN/COMMIT tx model, `rowcount > 0 else 0` DDL guard, `%`-escape on no-param SQL) and now have a regression unit test (`TestPgConvertSql`, incl. the `LIKE 'tick:%'` no-param case). Receipt-lore: the fix is in the STORE's resolution, not the receipt, so every `--script` consumer of DictStore/CacheWrapper (not just this test) stops silently going per-process. Gates this round: shard-mesh receipt 12/0, adapter-http-transport 5/0, adapter suite 10 files rc=0 zero script errors, data-naming 26/0, lint 37/0, pg-bridge 18/0, redis-bridge 20/0, real-postgres boot 5 migrations applied. Full parallel runner NOT run (owner instruction; being reworked).
  > **Last updated 2026-11-04 (shard-mesh Phase 0 round):** THE MESH'S FIRST TWO LEGS LANDED, AND THE SILENT SHARED-STATE BUG THAT WOULD HAVE BROKEN IT WAS FOUND. The Docker re-audit (does the image run the dev env AND the server as a shard?) closed as: dev env + single server YES, mesh NO -- and the why is now a design note, `labs/prd-shard-mesh.md` (intent vs reality table, the ENet-UDP-vs-WebSocket transport fork with a recommendation, and the 4-phase path; the "4-5 dockers acting as one" vision is arch doc sec.11.3/11.4, still Phase 1 single-process today). TWO CODE LEGS SHIPPED (Phase 0, transport-agnostic): (1) SHARD IDENTITY -- `ShardManager._ready` now reads SHARD_ID / SHARD_NAME / IS_PRIMARY / WORLD_SIZE_KM2 / MAX_PLAYERS_PER_SHARD and calls `configure()`, then `_register_with_coordinator()` announces the shard to CoordinatorService (an earlier autoload, so it is ready); no env -> shard_1/"Alpha"/primary, byte-identical to before. EMPTY COUNTS AS ABSENT (the receipt caught it): compose passes `SHARD_ID=${SHARD_ID:-}`, which `OS.has_environment` reports as PRESENT, so `_env_str` strips and empty-check compares -- `has_environment` alone would have configured every default container as shard_id="". (2) THE SHARED-STATE BUG: `DictStore` and `CacheWrapper` resolve their store through a STATIC `_adapter_registry` hook that NOTHING ever set -- `DictStore.set_adapter_registry`/`CacheWrapper.set_adapter_registry` had zero callers, so every DictStore (shard registry, coordinator registry, and every service ledger that rides "default") silently fell through to a PROCESS-LOCAL memory fallback. Two fixes: `BackendFactory.boot_defaults` now points both static hooks at AdapterRegistry, AND registers the "default" store name (it was never in STORE_MANIFEST, so `get_persistence("default")` returned null even with the hook set -- the two bugs together). With `STORAGE_BACKEND=postgres` the shard/coordinator registries now actually reach the shared store instead of evaporating per process. DEPLOY WIRING: Dockerfile gains `python3-psycopg python3-redis` (the bridges' real backends were lazy-imported but never installed, so postgres/redis were unreachable); compose's synmergia service gains STORAGE_BACKEND/CACHE_BACKEND/PG_BACKEND/REDIS_BACKEND/PG_BRIDGE_URL/REDIS_BRIDGE_URL + SHARD_ID/SHARD_NAME/IS_PRIMARY (all default to memory/sqlite/inmemory/empty = dev/CI unchanged); entrypoint.sh factors `_start_state_bridges()` and runs it in BOTH prod and headless (headless is the shard role -- previously it started no bridges at all, so a shard could not reach shared state). Receipt `tests/test_shard_mesh_identity.gd` exit 0 twelve legs (env identity, default identity, coordinator registration + name, two shards both registered, "default" store registered, DictStore round-trip through the registered store). NOT DONE (Phase 1+, tracked in the note): cross-shard bus transport, the edge transport decision, the N-shard compose topology. Gates: receipt 12/0, lint 37/0, compose config OK, entrypoint `bash -n` OK.
  > **Last updated 2026-11-04 (jewelry + loot-wiring round):** THE JEWELRY LINE OPENED, THE ABYSS PEARL GOT A THIRD SINK, AND THE ELITE TABLE PAID GOLDEN FREIGHT. (1) FOUR ACCESSORIES (data/accessories, slots 9 = ring / 11 = necklace, accessory_type law held): acc_ring_tidecaller (L6 ring, wis 2 vit 1, 36/90 -- braided kelp around a smith's iron band, the kelp economy speaks again), acc_ring_golden_signet (the Ledger Warder's Signet, L10, vit 2 str 2, 140/380 -- tempered gold cut with the Concord pillar, the debtor's answer to the creditor's seal), acc_necklace_paleshard_ward (L14 necklace, wis 3 int 2, 1050/2600 -- a mythril shard over an abyss pearl), acc_ring_starbinder (L18, wis 3 vit 3, 2000/5600 -- starmetal over its own pearl). bind_on_equip per the accessory law. (2) FOUR BILLS: tidecaller ring (WORKBENCH req 6: 4 kelp + 1 iron ingot), golden signet (FORGE req 10: 1 golden + 1 silver ingot), paleshard ward (WORKBENCH req 14: 1 mythril + 1 abyss pearl + 2 kelp), starbinder ring (FORGE req 18: 1 starmetal + 1 pearl). THE ABYSS PEARL is now a THREE-SINK reagent: the breather (the sea law), the paleshard ward, the starbinder ring -- the trench dive pays in jewelry now, not just air. (3) THE ELITE GATE: loot_elite_ore (the trolls' and void lord's SECONDARY table) gained the golden freight at honest odds -- wep_golden_estoc 0.12 / arm_golden_scale_chest 0.10 / acc_ring_golden_signet 0.08 beside the ore columns -- so the L10 tier is EARNABLE in the world, not only forgeable or shop-able; the mythril and starmetal tiers stay craft + 12-sigil depths (gear paths stay split by tier, not by luck). GATES: catalog 10/0 (28 recipes / 164 icon paths -- 4 jewelry icons minted), craft probe 13 checks exit 0, naming 26/0, lint 37/0. DEFERRED: gems as cutting inputs for the star-tier jewelry, a cloak/belt epic line, and the twin accessories' spirit book (breather shards ride one slot; two rings stay one-slot-one-body by the equip law).
  > **Last updated 2026-11-04 (deep metal ladder round):** THE THREE SINKLESS METALS LEARNED THEIR TRADES AND THE LADDER GREW ITS TOP. (1) THE GAP: ore_golden / ore_mythril / ore_starmetal were already MINED and LOOTED (loot_elite_ore drops all three and its own lore text promises the deep grades) but NO RECIPE consumed them -- three sinkless ores sat at buy 95/1200/320 with nowhere to go. (2) THE INGOTS: res_golden_ingot (2 ores, forge req 5, 88/190), res_mythril_ingot (2 pale ores BOUND THROUGH a golden ingot -- the mythril refuses a lone fire; 1100/2900), res_starmetal_ingot (2 ores through a mythril ingot -- sky metal wants the deepest binder; 300/760), each a slager byproduct smelt. The tier line climbs the binder chain: gold -> mythril -> starmetal, so a starmetal piece costs 6 ores + 1 gold + 1 mythril by construction. (3) THE GEAR: wep_golden_estoc (SWORD L10, 12-19 @ 1.2, str 6 vit 1, 165/450), wep_mythril_halberd (SPEAR L14, 15-26 @ 1.0, str 8 agi 2, 950/2600), wep_starmetal_skysplitter (the Concord's signed Starmetal Greatblade, L18 greatsword 20-34 @ 0.9, str 10 vit 2, 1800/5200); arm_golden_scale_chest (MAIL L10, armor 26, 200/560), arm_mythril_wardmail (MAIL L14, armor 34 + wis 2, 1100/3200), arm_starmetal_bulwark (PLATE L18, armor 44, 2000/6000). Purse and REQUIREMENTS laws held on first pass this round (the ladder law verified the climb L4->L18 without a defect). (4) THE BILLS: nine recipes (3 smelts + estoc/scale at forge req 10, halberd/halberd-binder at forge + wardmail at WORKBENCH req 14, skysplitter/bulwark forge req 18 with mooncap grip resin and mythril binders), failure rates .1-.2 as tier law. (5) THE DEPTHS PULL GREW ITS OWN TOP: loot_black_market_depths gained wep_starmetal_skysplitter (weight 9) + arm_starmetal_bulwark (weight 8) at the head of entries per that table's own documented append law -- the deep roll now dreams of the deep steel, and the 12-sigil price finally has endgame freight above the iron sword tier. GATES: catalog 10/0 (24 recipes, 160 icon paths), craft probe 13 checks exit 0 on the 24-recipe catalog, naming 26/0, lint 37/0, gamble receipt ALL-OK on the extended depths table, gen_icons 9 mints / 0 residue. DEFERRED: a golden/mythril ACCESSORY line (rings + amulets + their bills), gems as jewelry inputs, and weapon/armor tiers riding the black-market TIDE table (the shallow wash stays starter-priced).
  > **Last updated 2026-11-04 (item use + vendor + icons round):** THE POTIONS BECAME DRINKS, THE SMITHY BECAME A SHOP, AND THE ICONS STOPPED BEING ASPIRATIONS. (1) THE USE DOOR (InventoryService.use_item): the whole project's consumables carried a buff_effects book nobody ever read -- the door is the CONSUMER, not a schema change. GATES BEFORE EVERYTHING (each refusal names itself and pays nothing): real bag/slot/item, CONSUMABLE category, a live body (registered entity, else local player; the 'no body' rail is honest in headless boots), required_level inside the body's level, a non-inert book, the PER-ITEM use cooldown (a potion's cooldown is the ITEM's own field, not a service namespace -- the bag's use door keeps its own book keyed [player][item] -> expiry; CooldownService's books price COOLDOWNS by action key and cannot carry per-item durations). VALIDATE-THEN-PAY: the whole book validates (every buff a known type with usable values, timed effects carrying durations) BEFORE one charge leaves the slot -- books never half-drink; then ONE charge out, then effects land: instant_heal/instant_mana/instant_stamina through the body's duck surface, heal_over_time + stat_buff as REAL StatusEffect nodes riding the entity's own apply_status_effect law (the skill precedent: stat mods in, the body's own duration tick timer expires them, tick budgets self-expire HoTs). Unknown type / zero value / undated timed effect = whole-use refusal.THE RECEIPT tests/test_item_use.gd joins DEFAULT_SET (110 tests): all rails by name, validate-then-pay (a bad book consumes NOTHING), heal 40->90 + one-charge algebra, the cooldown book (refusal -> booked expiry -> a wound-back key re-opens the door), a real-Entity stat buff (+8 strength rides in, expires through the body's OWN timer, unwinds), a real HoT (heals across ticks, self-expires on its tick budget), mana through restore_mana, and the static law: EVERY authored consumable's book validates clean through the door's own validator. The door carries the transport seam (_use_body_override injectable resolver; runtime rides the default chain). (2) THE SMITHY'S SHOP: npc_blacksmith_village vendored NOTHING all its life (repairs + chat); its includes now open 'Smithy's Iron Ladder' (data/npc_offerings/vendor_smithy_iron.tres): the by_item_id iron ladder authored last round (dagger/axe/spear, the full leather set, the mail coat) + refined ingot stocks iron 20 / silver 10, priced 1.0, LIMITED stock (5/2 per row, daily restock), buy_categories [0,1,4] so the smithy pays for ore and broken gear. (3) THE ICON LAW IS REAL: scripts/gen_icons.py (stdlib-only PNG writer) MINTED all referenced res://icons/... (131 now) as deterministic 32x32 RGBA silhouette placeholders (family palette + hash hue jitter + per-keyword shape motifs: flask potions, blade weapons, diamond ores, ring currency, arch mounts...); idempotent re-runs keep, --force re-mints; the catalog receipt's new ICON LAW refuses any data icon_path that names no file (151 references pass). (4) NEW CONTENT RIDING THE DOOR: res_silver_ingot + recipe_silver_ingot (2 pale ores -> 1 ingot, forge, req 2, slag), the walnut staff's ferrule now pulls the REFINED ingot instead of raw ore; potion_mana_small (instant_mana 40) + recipe (mooncap + moonpetal, alchemy req 2), tea_mooncap_steep (HoT 25 x 8 s every 2 s) + recipe, elixir_ironblood (strength +8 / 45 s) + recipe (2 ore grit + petal req 4) -- each exercising one of the door's effect families. THE CATALOG RECEIPT GREW THREE MORE LAWS (10 legs now): VENDOR STOCK LAW (every offering types cleanly; every vendor shelf reflects service truth -- phantom skus, zero quantities, unpriced rows, dead stock modes refuse; by_category shelves resolve to >=1 real item), OFFERING INCLUDE LAW (every npc includes resolves to its real file: offering/vendor -> npc_offerings, inline dialogue -> dialogues, quest ids -> quests -- 18 npcs clean, zero phantoms), and the ICON LAW above. THE LAWS EARNED THEIR GATES TWICE: the two new timed drinkables had the same missing item_level key the soul gem had (authored honestly now: = required_level), and the fixer's ancient coin shelf was unpriced (buy 0 / sell 25) -- the ledger now buys coins at 60 so the melt law holds. GATES: item use 36/0 exit 0, catalog 10/0, craft probe 13 checks 0 fails (15 recipes), deep economy exit 0, naming 26/0, lint 37/0, packs 9/9 unfiled + packstruct --deep clean, DEFAULT_SET 110. DEFERRED: use_skill_id routes through SkillService (the door refuses that shape by name until that lane), the VendorService price_override field is DECLARED but its reader never existed (pricing paths read item.buy_price only -- wire the reader or drop the field in a vendor round), placeholder art until an asset pass.
  > **Last updated 2026-11-04 (item-catalog authoring round):** THE CATALOG LEARNED ITS IRON LADDER AND A RECEIPT THAT REFUSES PHANTOMS. (1) NINETEEN NEW .tres: data/weapons grew wep_iron_dagger / wep_iron_axe / wep_iron_spear (the forge ladder, honest stat + req + price lines), wep_longbow (Haven Shorebow: timber laminae + a braided Kelp Fiber string, the S14.7 kelp's OWN economy use) and wep_walnut_staff (silver ferrule + mooncap grip resin); data/armors grew the full leather set (helm / legs / boots / gloves) + arm_iron_mail_chest (5-ingot riveted, the forge L8 wall) + arm_cartographer_belt (the Concord's own buckle work); data/consumables grew potion_health_medium (instant_heal 120, the small potion's exact shape -- NOTE the buff_effects consumer is STILL un-wired: the small potion's book is just as inert, a deferred use-effects round); data/recipes grew seven honest bills: dagger / axe / spear (forge, slag byproducts), Shorebow (workbench, timber+kelp), staff (workbench, timber+silver ore+mooncap), mail coat (forge, 5 ingots, failure 0.15), and the potion steep (alchemy, moonpetal x2 + mooncap). (2) THE CATALOG RECEIPT: tests/test_item_catalog.gd joins DEFAULT_SET (109) -- family identity + prefix laws + filename==id across all five item families, the honest word/tag law, the PURSE law (sell >= 0, for-sale sells below it buys, zero/zero = quest only), stack law, the requirements-stay-inside law, weapon damage windows/speeds, armor values (the shield law: armor_value OR stats["armor"]), the price ladder (buy climbs with item level, never dips), service truth (every id get_item()s), and the BILLS: every recipe reflects the service -- station valid, inputs nonempty/unique/positive, phantom-input/PHANTOM-OUTPUT refusal riding BOTH grant laws (get_item for the bag, get_mount for the ownership wing: gliders load as mounts through load_mounts' data/gliders merge, so recipe_weaver_kite's glider output is LAWFUL, not a phantom -- the receipt's first draft caught it as one and the craft grant path taught the law). THE RECEIPT EARNED ITS GATES: potion_soul_gem had NO item_level (defaults 1) while required_level 10 and a 1000/5000 purse -- item_level = 10 authored; item_ancient_coin carried a zero/zero purse (an ancient coin no vendor buys AND no vendor sells is a lie) -- now sells for 25. GATES: item catalog 7/0 exit 0 (runner DEFAULT_SET now 109), probe_crafting 14 legs exit 0 on the 11-recipe catalog, naming 26/0, lint 37/0, packs regenerated 9 / 8 unfiled + packstruct --deep 0 errors, deep-economy receipt exit 0. Icons remain res://icons/... paths with no on-disk files (the pre-existing aspirational law, deferred to an asset round).
  > **Last updated 2026-11-04 (#19 residual -- the fence's frame drain):** THE WORLD'S DEATH STOPPED WAITING ON ITS WORKERS AND THE WORKERS STOPPED DYING UNREAPED WHEREVER FRAMES REMAIN. The first fence's whole bounded join lived inside _exit_tree -- a world swap froze <= 30 s while it polled, and the parked-straggler residue stayed. THE FENCE IS A THREE-PHASE LAW now (globe_terrain_streamer): (1) THE QUICK LAP, SYNC at async_shutdown -- marks closed (kickers refuse; both appliers go REAP-ONLY: a post-fence deferred apply joins its own thread, clears its pending flag, and touches NOTHING in the dying scene), then joins every worker that finishes inside its bounded FENCE_JOIN_WINDOW_MS window -- probe quits are THIS phase's fence (a quitting process starves the frame drain of frames), so the shipped fence's window is preserved, not replaced. (2) THE FRAME DRAIN, the non-blocking law the icosahedral round left for this round: a coroutine ON THE ORPHANED STREAMER OBJECT (it is never a tree child, so the object, its coroutine, and its Thread books survive world free) awaits engine frames until pending_derive() == 0 -- the applies flush on those frames and each reaps its own worker -- or the window wall. _exit_tree returns IMMEDIATELY: a scene swap pays ~zero fence wall in-tree. A drain parked on no further frames simply never resumes (the dropped-straggler residue, not a new hazard; the orphaned object is the pre-existing lifetime, not a leak). (3) THE DECISIVE LAP, bounded FENCE_FINAL_JOIN_MS (2 s): a last reap for the finishes the drain raced, then the books clear under their own mutexes; a still-parked worker past it is DROPPED (its Thread dies unjoined -- the engine-internal futex straggler class; the shipped fence's one honest residue). MEASURED on today's runner (-j 1, same box): probe_stream_continent_a exit = PASS with 3 SCRIPT ERROR + 1 thread warning, vs the SAME-DAY HEAD control (fix stashed) PASS with 3 + 3 -- the shipped band held, one unjoined-worker WARNING fewer (the frame drain reaped a mid-flight finish the window dropped). An earlier draft with a too-short 1.5 s quick lap scored 4 + 4 and was FALSIFIED + fixed: the quit path NEEDS the full window; the frame drain cannot rescue a quit. Drained boots (probe_planet_rebase_20km, probe_terrain_backend, test_terrain_determinism) PASS; lint 37/0. Parse-note: --check-only artifact counts on both touched files identical pre/post (22 / 14: the documented autoload-identifier artifact). Fence lore: THE AWAIT is the streamer's own law (Engine.get_main_loop() -> `ml is SceneTree` guard -> `await ml.process_frame`); NOTE a GDScript method containing `await` is a coroutine -- async_shutdown() now returns at its first call continuation and callers must NOT await it (globe_world._exit_tree does fire-and-forget, by design).
  > **Last updated 2026-11-04 (dev-setup + docker-audit round):** THE DEV TOOLCHAIN BECAME REPRODUCIBLE FROM THE REPO ALONE, AND THE IMAGE WAS AUDITED FOR REAL DEFECTS. NEW `scripts/setup-dev.sh`: one-command host bootstrap (system libs + Godot + Node + bun) that reads its apt package list and the GODOT_VERSION / NODE_VERSION pins STRAIGHT OUT OF THE `Dockerfile` (awk over the `apt-get install` block) so the host script and the container image cannot drift; flags `--with-templates` (web export, ~800MB) / `--with-blender` (3D pipeline) / `--with-web-probe` (chromium) / `--all` / `--skip-apt` / `--dry-run` / `--prefix DIR`; installs into `~/.local` (no root needed for the binaries), idempotent, arch-aware (x86_64/arm64), PATH wired into rc files. THREE REAL DOCKER DEFECTS FIXED: (1) THE IMAGE COULD NOT BUILD -- `debian:trixie-slim` renamed `libasound2` / `libgtk-3-0` / `libatk-bridge2.0-0` to their time64 ABI variants (`libasound2t64` etc) and the bare names no longer resolve, so the apt line aborted on all three (verified against the live trixie index: bare = NOT AVAILABLE, t64 = present; `apt-get install -s` of the full 49-package list exits 0); (2) `srv/` WAS NEVER IN THE IMAGE -- the entrypoint runs the pg/redis/webhook bridges + the NOAA Kp sidecar from `/workspace/project/srv/` and compose mounts only `./game` + `./labs`, so test/prod modes died at the first `python3 .../main.py`; added `COPY srv/` (game/ stays runtime-supplied on purpose, baking it would be dead weight); (3) THE TEST-MODE GODOT LOOP WAS A FALSE GREEN -- it globbed `game/tests/*.gd` from inside `game/` (matches nothing) and ran `res://<basename>` (a path that does not exist), so the loop ran ZERO tests and still logged "All smoke tests passed"; now globs `tests/*.gd` with `res://tests/<file>`. Docs: DEVCODE.md sec 1/6 + README point at `setup-dev.sh`. First PR off `staging` (PR-base-staging law). Gates: `bash -n` clean, `--dry-run` resolves 49 pkgs + Godot 4.7.2 + Node 20.20.2, full install tested end-to-end in an isolated prefix (godot/node/bun all land, re-run is a no-op), apt `-s` of the whole list exits 0.
  > **Last updated 2026-11-05 (shard mesh Phase 2 -- edge transport):** THE EDGE GOT A DOOR AN L7 CAN OPEN. Phase 1 gave the coordinator a cross-shard bus (`game/core/mesh/`); Phase 2 (the edge -- how a client reaches a shard behind a proxy) is `NetworkManager`. DECISION: Option B (WebSocket server + nginx L7), Option A (ENet+UDP) retained for native-direct. `EDGE_TRANSPORT` selects the server transport: `enet` (default, byte-identical) or `websocket` (aliases `ws`/`wss`, case-insensitive; empty/unknown -> enet with a warn, never a boot failure). `_resolve_edge_transport()` reads the env at `_ready`; `_make_server_peer(port)` builds `ENetMultiplayerPeer.create_server` or `WebSocketMultiplayerPeer.create_server`; `start_server`/`connect_to_server` ride it unchanged (a websocket mesh now routes native clients through the same client path browsers already used). `get_connection_info()` reports `edge_transport`. nginx: the `godot` upstream carries `ip_hash` (sticky routing -- a WS upgrade and the client's follow-up requests land on the same shard) and `GODOT_UPSTREAM` is now a comma/space list the entrypoint expands into one `server` line per shard (single host == the previous config; verified both shapes against a copy of nginx.conf). compose exposes `EDGE_TRANSPORT`. RECEIPT `tests/test_edge_transport.gd` (14 legs, runner DEFAULT_SET): env resolution (default/ws/wss/case/empty/unknown), `_make_server_peer` builds the right peer type, the websocket peer actually BINDS (reaches CONNECTION_CONNECTED -- the Option B capability), and connection-info reports the transport. Receipt-lore: a same-process WS client+server loopback does NOT complete in headless Godot (a known artifact; irrelevant in prod where they are separate processes) -- the receipt proves the SERVER bind, not the loopback. GATES: edge 14/0, shard bus 17/0, identity 12/0, adapter HTTP 5/0, data-naming 26/0, lint 37/0.
> **Last updated 2026-11-05 (shard mesh Phase 1 -- cross-shard bus):** THE COORDINATOR LEARNED TO SPEAK ACROSS PROCESSES. `game/core/mesh/`: `shard_bus.gd` (contract: subscribe/publish/poll; per-(subscriber,topic) mailbox; NO-ECHO law), `memory_shard_bus.gd` (process-local default, shared static store), `redis_shard_bus.gd` (over the redis-bridge sidecar), `shard_bus_registry.gd` (plugin board -- re-registering an id REPLACES it, `make_default` re-points). `CoordinatorService` publishes on every `emit_cross_shard_event` and drains remote mail inside `get_pending_events`, so remote events ride the same exactly-once path as local emits. `SHARD_BUS_BACKEND` selects the transport (default: follow `CACHE_BACKEND`); a failed Redis connect falls back to memory rather than failing the boot. DRIVE-BY: `redis_store.gd::_blocking_get` no longer types the retry result's `.data` as Dictionary (null on the unreachable-bridge path -> "assign Nil to Dictionary"); the honest fallback makes that path real. Receipt `tests/test_shard_bus.gd` 17/0. (Round note landed with PR #52; this line records it.)
> **Last updated 2026-11-04 (staging-branch law):** WORK LANDED ON `staging`, NOT `main` — Buffy AND the OpenHands agents both develop + push to `staging` (private repo: every main push is an Actions bill; staging pushes are free since web-ci's push path only triggers on main). Full test gates stay LOCAL (the parallel runner, `scripts/godot_test_parallel.sh`, full-gates-local by owner instruction) — CI is never the gate. PROMOTION is the periodic manual act: fast-forward `staging` onto main's tip first (never develop off a stale staging), merge `--no-ff` to main `staging` -> `main` so promote points stay visible, push main once (one ~2-min CI run does the pck export + commit-back). PRs from OpenHands BASE ON `staging` and land through local verification + the merge through staging (same in-dock receipt/lint law, staged-then-promoted). Old law for reference below.
  > **Last updated 2026-11-04 (parallel sweep round):** THE FULL SWEEP STOPPED BEING A 90-MINUTE SERIAL MARCH. `scripts/godot_test_parallel.sh` is the runner's bash sister with the SAME laws (per-test boot, per-test timeout, /tmp/syn_*.log, "N passed, M failed" + exit-iff-green) but N CONCURRENT boots; three laws make it honest instead of lucky: (1) the .godot import cache is WARM-BOOTED once single-threaded first (a cold cache hit by N importers is exactly the continent shards' "abort only under concurrent load" noise class); (2) workers share nothing but the warm cache (per-test logs, status files, frame/ two-location resolution kept); (3) NO blind auto-retry hides a real break -- --resume FILE carries a killed run (skips passed names, appends new passes, a flake re-runs BY NAME and visibly). Usage: `sh scripts/godot_test_parallel.sh [-j N] [names...] | --all` (JOBS capped at 2x cores; a worker is a full boot with its own derive threads). MEASURED on the 2-core sandbox: 8 tests 21 s wall / 45 s CPU at -j 4, 27 tests 45 s wall / 2m09 CPU (~2.9x efficiency) -- the 90-minute full sweep drops to ~wall-time/jobs on fat hosts. web-ci's Optional Full Test Suite dropped the serial find|for march for `--all -j 4` (step stays non-gating as before). PR round same turn: OpenHands #47 landed (`827fd6d3`, hud_services wiring restored into `_connect_services`, receipt 10/0) and #49 landed (`be5caa75`, party death notify through `PartyService.get_player_party`, receipt 5/0); lint green on the merged tree; no full run this round by owner instruction.
> **Last updated 2026-11-04 (PR-45 merge + S14.7.4 deferral round):** THE DEATH BOOKS PAID, THE STRAIT'S PINS GOT THEIR BUOYS, AND THE GARDEN'S PAINT LEARNED PER-PLANT TRUTH. (0) THE MERGE: OpenHands' PR #45 landed as-is (`08b6e46f`, closes #44): death_features.gd's payout legs were guarded by `has_method()` on methods NO class declares (`get_xp`/`get_gold`/`modify_xp`/`modify_gold`/`get_zone_id`), so kill-streak rewards toasted a phantom payout (+N XP, +N gold that never moved) and death penalties no-opped; the legs now pay through the real duck-typed wallet surface (`experience`/`gold` fields + `add_experience`/`add_gold`, clamped spends, `experience_changed` re-announce, a signed delta mirrored into PlayerManager for the local body) and the death-history zone id routes through `ZoneManager.get_entity_zone_id()`. Receipt `test_death_progression_surface` (18 legs) joins the repo on main as landed-not-DEFAULT (verified 18/0 + the death cluster neighbors + lint). (1) THE STRAIT BUOYS (harbor_lights.gd + globe_world): the barque's two pins get their harbor marks -- `build_strait_buoys()` stands a floating drum + ring band + moor shaft + slim mast + amber lamp ON the sea line at ONE BEACON_FLANK_STEP off each berth (so the hull never touches its own marker; a buoy is not a moor bank -- its base IS the sea line, no walk read by design), carrying the SAME `lamp`/`halo` metas the pier beacon does, so `_barque_ferry_tick` flips both with `HARBOR_LIGHTS.place_night` off the epoch it already holds (lit dusk to dawn, dark to the sun). (2) PER-PLANT PAINT (S14.7.4): the whole-cove hide is GONE. The DERIVE now replays the REGISTER call's jitter seed-for-seed (`base_acc + 9091 + bed_idx*101`, the same three randf_range per plant) so the paint learns each registered plant's real dir, tags every kelp strand / vent spire with the nearest plant's `plant_k`, and mints ONE hidden stump per plant (`Stump0..2`, plant's own material, `plant_k` meta). The binder's refresh is per plant now: the cove's furniture (reef boulders, drowned stones) STANDS through every take -- a taken plant shears to its stump until THAT plant's respawn; ids say nothing -> untouched (fail-open on paint, and paint never invents depletion). Swim receipt H legs re-lawed (one-plant shear, bed's other plants keep paint, furniture stands, cove never vanishes, all-taken all-stumps, respawn restores); the two stale material-count legs count by NAME now (stumps share the bed's material by design), and the shelf-face stump leg reads ALL beds on the face (a face can own kelp AND trench beds). (3) THE SEABAR'S OWN _READY: new receipt `test_sea_bar_hud_ready.gd` (runner DEFAULT_SET -- 108) walks the REAL HUD seam: hud_layer.tscn instantiates, `_ready()` installs SeaBar (named SeaBar, hidden dry), the wet legs read the INSTALLED chip (band SURFACE-SWIM rename / SQUEEZE, breath ratio, pressure row, DROWNING flash, dry hide), and the poll law rides the bar's own `_process` against PlayerManager's local slot (bind shows, clear hides; bounded waits so a dead heartbeat cannot hang the receipt). (4) THE DOCK-WARP TIER RIDES THE BARQUE: `_execute_wake_warp` routes the landing by vehicle_id -- the runner's gateways land at the capitol pier / pans moor bank as before, the barque's land at HER OWN pins read from the VESSEL'S OWN lane metas (the hull's lane is the sailor's landing, never a re-derived bearing), and the landing radius carries the vessel law's own `max(walk, sea)` clamp so a warp never spawns a body UNDER the water line (drowning takes the body only by its own swim). FerryService's tier was already generic; the world owned the landing and now has it. Barque receipt grew the tier legs: unearned warp refused by name ('not yours yet'), three deck wakes make the wake known, the earned warp emits vehicle + pin true, and the landing law tested against a real-streamer-shape stub (seabed walk never lands under the sea line; foreign pins have no landing = INF). GATES: swim receipt 60/0 exit 0, barque receipt green (buoys + warp legs, exit 0), SeaBar HUD receipt PASS, lint green (5 files), fleet packs regenerated 9 packs / 7 unfiled + packstruct --deep green; full default pipeline coverage GREEN on the final tree via the resume ledger over the runner's own per-test boots (106 unique names all exit-0-PASS; four cloud restarts killed four uninterrupted tails, the ledger owns the coverage -- the sweep DID catch probe_crafting's die-flake: its synthetic leg ran one un-seeded roll and now drives the same chain itself, roll-agnostic for any die).

> **Last updated 2026-11-04 (PR-43 merge + S14.7.3 barque/binder/damage round):** THE STRAIT'S SCHEDULED RIDE BECAME REAL PAINT, THE GARDEN'S PAINT FOLLOWED ITS TRUTH, AND THE SEA BEGAN TO DROWN THE CARELESS. (0) THE MERGE: PR #43 landed as-is (OpenHands' UIManager fix, `24e1631b`): `has_method()` on SIGNAL names is always false, so UIManager's three GameManager connects were silently dead all project life -- `_initialize_ui()` never ran, TargetTooltip never spawned. Guarded with `has_signal()` + connected de-dupe, autoloads resolved at runtime (script-mode-safe), `TargetingManager.get_local_player_id()` added (the phantom call next door), and a static lint guard now flags `has_method("signal_name")` repo-wide (lint is 37 checks now). Receipt `test_ui_manager_tooltip_wiring` 11/0 joins DEFAULT_SET -- 107 tests. (1) THE BARQUE (globe_world, ferry_vessel): the data route `veh_sundered_barque` (6 casts/day, first 5.5 h, 0.6 h crossing) stood without a hull all this time; `ferry_vessel.gd` gained `build_vessel()` (one generic builder -- the same piece-collider hull, the same `place()` law, guarded by lane metas) and `build_barque()` (the two pins' own dirs from DATA: `DataService.get_gateway("waypoint_strait_moor"/"waypoint_strait_seaward").source_position`, always the gateway's own truth, never an in-file bearing); the Pans runner's build() delegates to build_vessel. `_build_sundered_barque()` boots her with the runner's tick law (FerrySchedule + place() + deck carry) and her own roof of DECK WAKE bookkeepers (the runner's original weak wake glue is kept untouched on purpose). The lane arcs across the strait to the two gateway pins, hull floats ON the world sea line mid-crossing, berthed lifts at both ends. (2) THE WAKE TICK SHAPE: the barque's berthing glue plans `at_sea` BEFORE it clears the seen-roster — a body marked on a sea tick is credited at the very next berth, the runner-law shape just without the runner's old edge. (3) THE BINDING (deep_garden_binder.gd new law + streamer metas): the garden grove grove's no longer just paint -- the register call now stamps `deep_garden` groups and `harvest_ids` metas on each (face, bed) grove, and the world-side binder joins HarvestService's depletion book to the paint: while ALL three of a bed's plants are depleted the cove hides its kelp/pearls until a respawn reveals it; leaf-empty beds (never registered, e.g. a bare host) keep paint without pretending anything was taken. Binding is idempotent (dock-meta guard across re-inits and re-derives). (4) THE SEA OWNS THE BODY IN FULL: globe_player's swim step now reads breath/pressure/burn/drowning from `tick_swimmer`, books them (`_sea_breath_s/_max`, `_sea_pressure`, `_sea_drowning_s`, `_sea_burn_dps`), and pays: drowning (10 dps past an empty breath), the pressure pool (pool = rate, drained at mult 1), and any non-water burn each march a damage debt that drops through `take_damage` in whole points; surfacing wipes the debt (health never heals from a surface, the pool eased by the service's law). The MOUNT HANDOFF also got its feed (RideService.water_stamp_for): before the tick, the sea step asks the ride service for the mount's stamp -- a swimmer mount's grace/crush-bonus/current-immunity enter the SAME tick call (a mounted body and a naked body obey one ocean law), a land mount past the waterline is dismissed by the service itself, no ride service means the naked path unchanged. (5) THE HUD: SeaBar (ui/components/sea_bar.gd, the StormBar dialect) under HudLayer next to StormBar, polls the local body's swim book at 0.15 s, hidden while dry: band row (SURFACE SWIM / SUBMERGED / SQUEEZE / CRUSH), BREATH bar (fraction of breather capacity), DROWNING flash at zero, the pressure pool row. The same posture the horde bar keeps: the damage is the body's law, the bar only tells the truth about it. (6) THE FORD PROBE'S DRY LEG LANDED: probe_terrain_planet measured "dry" walk at a spring's antipode -- under the S14.7 radial sea that antipode can be open ocean on the Sundered backend, so the S14.7.2 sea step then took a "dry" body standing on the seabed (CRUSH band) and the dry speed leg collapsed (ratio 133.33; the last full pipeline had been waived two rounds straight so nothing caught it). The dry site is the hydro law's OWN guaranteed-dry ground now (the spawn apron, flat 28 m): PASS by law, not by accident of geography. RECEIPTS: swim 52/0 (added legs: mount grace re-bands the body, the ride law is asked, a dismissed land mount still obeys the sea, breath/pressure books drain through health, surfacing wipes the debt without a heal, SeaBar band/breath/pressure/drowning rows plus dry-hidden, grove identity metas + full-take hides + respawn reveals); barque 16/0 (route status honest, both pins' gateway dirs, one piece-collider hull, lane metas, floats on the sea line mid-lane, berths at the pins). GATES: receipts 52/0 + 16/0 + 11/0, lint 37/0 (the new guard green, 5 files), full pipeline rerun recorded in the TASKS log below, packs 9/6 unfiled + packstruct --deep green. Deferred: the dock hemp-off ferry moor buoys for the two strait pins, a SeaBar integration test through hud_layer's own _ready, ride entities for the garden's props (kelp stumps when partially taken -- paint-per-plant rather than paint-per-bed), and the wake_known dock-warp tier riding the barque.
> **Last updated 2026-11-04 (S14.7.2 Sundered Sea deep garden + sea body):** THE DEEP SHELF GOT A WORLD AND THE BODY LEARNED TO SWIM IT. Data alone cannot be a sea: S14.7.1 authored the bands and the current, this round puts them in the world. (1) THE DEEP GARDEN (globe_terrain_streamer): SIX AUTHORED BEDS on the strait chart (`DEEP_BEDS`: kelp shelf at x 0.40/0.45/0.50 with y -0.07/0/0.07, trench pearls at 0.58/0.64/0.70 with y -0.04/0/0.04) resolve through `StraitChart.dir_from_chart` onto the real sphere, and the bed direction's OWN FACE (the `IcosahedralFaces` lookup) owns it -- `_deep_beds_for_face(face)` is the ONE placement law read by BOTH the harvest registration and the prop build, so a bed you can see is a bed you can take. A face may own more than one bed (a 21 km patch is large next to the chart), and each bed keeps its own identity (`deep_kelp_<face>_<bed>_<k>`, `DeepGarden<face>_<bed>`) -- the first draft assumed one bed per face and was falsified by the receipt. Registration rides `_kick_prop_derivation` BESIDE the strait freight (main thread, service side effect, never worker work): three live HarvestService nodes per bed on the res_ ids the S14.7.1 economy reads, ids seed-stable per (face, bed), depth jitter clamped INSIDE the authored band (kelp 30-45, pearls 50-58), positions on the RADIAL SEA LINE (`OceanService.sea_surface_radius()` -- one sea truth, resolved by the service; the shell is the fallback when no service exists). Respawn is authored past the tide: kelp 420 s, pearls 900 s. (2) THE DRAW (same face, same beds): kelp beds paint FOURTEEN strands (7-14 m tapered cylinders, radial basis off the bed direction, the shared prop mesh registry + ONE cached kelp material) and four reef boulders; trench beds paint six pale vent spires and two drowned stones; children sit in the patch's local frame through `_tangent_patch_local` exactly like trees and rocks, so a streamed-out face takes its garden with it and a revisit re-derives the same grove. (3) THE SEA STEP (globe_player): the world body finally answers the water. `_sea_swim_step(delta, up, wish)` calls `OceanService.tick_swimmer` ONCE with the breather's grace + `current_immune`, and obeys the returned band -- DRY/WADING return false (the river ford law keeps its bands, untouched), SUBMERGED/SQUEEZE/CRUSH take the body: swim pace = walk x 0.62 steered at 4/s, the volume's CURRENT added on top at its own declared flow (the FERRY LANE: 0.5 m/s along the Sundered RUN tangent; a current-immune breather reads ZERO from the service, the one seam), buoyancy springs onto a 0.6 m float depth unless crouch dives or jump climbs, and CRUSH ignores the wish and pushes up (the ocean says no). `_sea_carry` is the applied horizontal book (HUD/anticheat next). Leaving the water forgets the swimmer book. RECEIPT `tests/test_sundered_sea_swim.gd` (runner DEFAULT_SET -- 105 now; fleet packs regenerated 9 packs / 4 unfiled sets, packstruct --deep green) 32 checks / 0 fails: six beds each owned exactly once, real owning faces, a non-bed face owning nothing, per-kind draw counts (14 kelp + boulders / 6 spires + stones, and a mixed face draws only its own shelf kelp), no draw on a non-bed face, three harvest nodes per bed with the right res_ id + band + sea-line depth, id-stable re-registration, and the body legs (dry keeps the walk, 38 m down is taken, band >= SUBMERGED, depth read, the declared current > 0.4 m/s along RUN, `_sea_carry` == the volume flow, idle float upward, immunity zeroing the flow, leaving clears the book). GATES: receipt 32/0 exit 0, lint 36/0, packstruct --deep green, continent-shard boot probe on the changed streamer (result in labs/TASKS.md). Deferred: node-in-world PROP-ENTITY binding (the harvest nodes are service truth; the garden mesh is the paint), breath/pressure DAMAGE conversion + HUD meters, the ferry as a scheduled ride (FerryService already owns the schedule; the drift is the lane today), and water mounts riding the sea bands.
> **Last updated 2026-11-04 (roster + client-dispatch round):** TWO PHANTOM-CALL SEAMS DIED (issues #34/#35). (1) THE ROSTER API: admin/targeting surfaces asked `PlayerManager` for `get_player_info` / `get_all_players` / `get_online_player_ids` / `is_player_online` -- none of which existed, so every admin command path, the permission session check and `requires_target_online` targeting raised "Nonexistent function ... in base 'Node (player_manager.gd)'". `PlayerManager` now owns the thin delegating helpers, backed by `EntityService`'s live registration (the ONE roster): rows are `{entity_id, name, level, online, permission_level}` built by duck-typing the live player node, "online" means a live player node is registered (`get_entity(id) != null`), never an invented character id, and permission comes from `PermissionManager.get_player_level` with PLAYER (0) as the floor. All reads node-resolve (`get_node_or_null`) instead of touching autoload identifiers, so bare hosts stay quiet. CONSUMER FIX: `admin_commands._find_entity_by_id`'s roster fallback did `p as Node3D` on what is now a dictionary row -- it resolves the row's `entity_id` back through `EntityService.get_entity` and returns the LIVE node (or null). (2) THE CLIENT DISPATCH: `NetworkManager._receive_client_message` called `InputManager.handle_client_input` / `InteractionLayer.handle_client_action` / `ChatService.handle_client_chat` -- three methods that never existed anywhere in the tree (latent: no in-repo producer sends those types yet, so it would have been an instant runtime throw on the first real client message). The dispatch is now honest: chat routes through the REAL `ChatService.send_message`, with the sender identity DERIVED from the peer's associated character (`get_character_for_peer`, the login mapping) -- the payload's own `sender_id` is ignored, so a client cannot speak as someone else; an unmapped peer is dropped by name; a channel resolves through `ChatService.channel_by_name` and falls back to SAY rather than inventing one. Input/action keep their wiring behind `has_method` guards (they call the handler if a manager ever grows one) and otherwise warn ONCE per type per process (`_unrouted_warned`), and unknown message types warn the same way instead of being silently swallowed. RECEIPT `tests/test_roster_and_dispatch.gd` (runner DEFAULT_SET, fleet packs regenerated -- 9 packs / 3 unfiled sets, packstruct --deep green) 37 checks / 0 fails: the four roster methods + `_handle_client_chat`/`_warn_unrouted` exist, `ChatService` has no phantom `handle_client_chat`, empty/unknown ids are honest (false/empty), a REAL registered player body yields the row (entity_id/display_name/level/online/permission_level) and lands in `get_online_player_ids` + `get_all_players`, the admin row-to-node lookup resolves the live body (and null for a stranger), a whisper from an unmapped peer is dropped while a mapped peer delivers exactly one row whose sender is the DERIVED character (the payload's forged sender never appears), unregistration clears online/rows/ids, and the unrouted book stays one line per type. Receipt lore: GDScript lambdas connected to typed signals should stay UNTYPED in the callback signature -- a typed lambda silently failed to receive `message_received` here; SAY also requires a living audience (`_get_channel_targets` empty = honest refusal), so the route leg uses WHISPER's explicit target. GATES: receipt 37/0 exit 0, lint 36/0, quest glide receipt 10/0, data-naming lint 26/0, packstruct --deep green; full pipeline deferred this round by owner instruction (the runner DEFAULT_SET is now 104). Also merged this turn: OpenHands' PR #41 (GLIDE objective + bridge, closes #40) as `94ecc77e`, draft PR #24 closed as already-satisfied (main's web-ci.yml already carries `mkdir -p builds/web-shell`).
> **Last updated 2026-11-04 (glide objective integrity round):** THE UNCOMPLETABLE GLIDE QUEST DIED. `quest_wings_over_haven` authored its only objective as a KILL (type 0) with the descriptive target `'glide 300 meters'` -- the KILL bridge credits enemy display_names (and BoutHostService's fabricated `TRIAL_DUMMY_NAME`), so NO credit path could ever produce that literal and the quest could never leave IN_PROGRESS. THE FIX IS A REAL OBJECTIVE TYPE: `QuestData.ObjectiveType.GLIDE` (13) with the one-id contract `target == "glide_distance"` (the SWIM precedent). ThermalService already accrued per-body glide distance (`record_glide_tick`, fed by the glider tick in globe_player + the underworld visitor tick) but spoke it ONLY to the gliding achievements; it now emits `glide_distance_reached(player_id, meters)` once per `GLIDE_QUEST_STEP` (300 m) boundary crossed, and `QuestService._connect_glide_bridge` (deferred connect, has_signal-guarded, the insight/swim pattern) routes it into GLIDE objectives. `globe_player.gd` flushes the glide session on the falling edge -- the wing AUTO-DEPLOYS near the ground, so a completed glide spans many frames and the old single-tick flush never landed; `_flush_glide_session` (Engine.get_main_loop() guarded) pushes distance/altitude/time once when GLIDING ends. THE STATIC GUARD (test_data_naming_lint): every authored objective target must resolve against the SAME catalog its credit bridge reads -- KILL->enemy display_name, COLLECT->item, EXPLORE->zone id, TALK->npc id, SWIM->ocean id, GLIDE->glide_distance, RECORD_INSIGHT->sky_insight; it scans inline AND multi-line `objectives = [...]` blocks (the multi-line form hid quest_intro_core_npcs from a first draft) and allows only `marshal's dummies` (entity-free trial dummies). It caught the real defect and the Awakening's stale TALK display-name target (the round-1 PR #39 fix, re-landed here). Receipt `tests/test_quest_glide_bridge.gd` exit 0 ten legs (deferred bridge connect, .tres shape, 299 m no-milestone / 300th fires once, real accept + 1/1 credit + COMPLETE, no over-tick, glide text row). Gates: pipeline exit 0 zero script errors, lint 36/0, data-naming 26/0.
> **Last updated 2026-11-04 (S14.7.1 Sundered Sea deep-shelf data pass):** THE WORLD SEA LEARNED ITS OWN WATERLINE. The Sundered Sea round's first increment ships as DATA + SERVICES (no fake visuals): (1) OceanVolume gained the RADIAL WATERLINE model (`waterline_is_radial`) -- the plane waterline is only honest where a scene is small; the 20 km world sea's waterline is a SPHERE. The pairing law binds it to radial rock, the receipt pins both. (2) OceanService resolves the sea's truth ONCE (`sea_surface_radius()` = DEFAULT_FLOOR_RADIUS 20000 + TerrainGen.sea_level(world_seed), runtime-cached; data volumes stay pure and can never disagree with the terrain that paints the water): radial volumes claim [floor_radius, sea_r + 2 m wading reach] in `volume_at`, and `sample_depth` reads the radial column (negative above the line, -1 inside the rock) -- the plane branch is untouched, so probe_ocean/probe_swim's Haven Shelf + Builder's Pool laws did not move a meter. (3) THE CURRENT LAW'S SEA EDITION: Item gained the `current_immune` accessory field (to_dict/from_dict legs ride too); `breather_for` speaks it; `tick_swimmer(..., current_immune)` stamps ZERO (the sea cannot carry the pearl-diver -- the same seam the water mounts ride). (4) HarvestService grew the DEPTH-BAND nodes (`register_node(..., min_depth_m, max_depth_m)`; 0 = ungated): `harvest` samples the ACTOR's body depth (PlayerManager local-body duck truth -> OceanService.sample_depth) and refuses BY NAME -- `not_in_water` (no body / dry / rock), `too_shallow`, `too_deep`, all BEFORE the depleted/rate gates -- fail closed: the deep garden cannot be taken blind from the shore. (5) THE DATA: `data/oceans/ocean_sundered_sea.tres` -- the world's first radial-waterline volume (floor_is_radial, center ZERO, floor_radius 19400, max_depth 60, pressure 0.1; current = backend_sundered's RUN tangent at 0.5 m/s, the ferry lane prd sec 8 promises); `res_kelp_fiber` + `res_abyss_pearl` reagents; `acc_breather_abyss_pearl` (x8 air, +20 m grace, current-immune necklace, level 8); `recipe_abyssal_breather` (1 pearl + 8 kelp, hand station); banding: reef kelp nodes 30-45 m, trench pearls 50-58 m (the squeeze line is 50; the pearl lives past it, the breather buys it back). RECEIPT: `tests/test_sundered_deep_economy.gd` (runner DEFAULT_SET -- fleet packs regenerated, 9 packs / 2 unfiled family sets, packstruct --deep green) 36 checks / 0 fails: the seed sea truth (waterline radius == shell + Gen.sea_level exactly), claim windows (+2 wading, inside-rock -1), RUN-lane current == BS.RUN_DIR.normalized()*0.5 with the immune tick reading ZERO, bands at 20/49/55/61 m, both node bands refusing by name and paying through the honest purse (3 kelp / 2 pearls after the grants), a no-body fail-closed leg, the craft gate (8 kelp alone nothing; 1+8 crafts), the breather equip + default-law reset + un-equip reset. GATES: receipt exit 0 36/0, lint 36/0, full pipeline exit=0 / **103 passed / 0 failed / 0 SCRIPT ERROR** (runner DEFAULT_SET now 103; the four long continent shards included), packstruct lint --deep exit 0. NEXT DUE (S14.7.2+): node-in-world registration in the streamer (the `_register_harvest_node` pattern, seed-stable ids), reef/kelp/trench visual props, globe_player swim integration with OceanService's radial waterline, and the current loop as a ferry ride lane.
> **Last updated 2026-11-04 (driver hookups + dialogue/quest round):** THE PLAY DRIVER'S SOCIAL/NAV HOOKUPS + TWO DIALOGUE/QUEST DEFECTS. THE DRIVER grew three stages in `playthrough_driver_runner.gd` (already in DEFAULT_SET -- extended in place, no fleet-pack regen): 15 WAYPOINT->COMPASS (`create_waypoint_here` + `activate_waypoint` opens the HUD Compass for the local player, out-of-bounds `create_waypoint` refuses, deactivate closes it -- the compass consumer had zero driver coverage), 16 FRIENDS (request -> accept -> block, asserting the observable loop state), 17 CHAT (a real party makes PARTY chat resolve a live audience, System lines always land, the ignore book hides a peer at ChatUI while System stays visible). THREE FIXES THE STAGES SURFACED: (a) `FriendsService.accept_friend_request` emitted BOTH `friend_request_accepted` AND `friend_request_declined` (copy-paste from decline) -- the false decline is gone (issue #38). (b) `quest_main_awakening.tres` (The Awakening, the game's FIRST quest) authored its TALK objective target as the display name `"Village Elder"`, but the TALK bridge credits by the NPCData id verbatim (`dialogue_ended` carries `npc_village_elder`; no display-name fallback), so the first quest was UNCOMPLETABLE and gated the chain behind it (`quest_main_teachings` requires it) -- fixed the data to the npc_ id (issue #37). (c) `test_data_naming_lint.gd` now asserts every TALK (type 5) objective names a real `npc_` id (RegEx over the objectives array) -- verified it flags the original data; the lint had checked giver/turn_in refs but never objective targets. This round also carries the `IcosahedralFaces` mutex-guarded `_ensure_built` (issue #36, the concurrent-build half of the #19 race; the entry below documents the fix itself). GATES: playthrough_driver 113 passed / 0 failed (was 78), full pipeline 102 passed / 0 failed / 0 SCRIPT ERROR / 0 aborts, lint syntax 7/0 + indentation 5/0 + general 12/0 + charset 3/0 + autoload 9/0, data-naming lint 26/0, quest/dialogue/social tests all exit 0.
> **Last updated 2026-11-04 (icosahedral lazy-init race round):** ISSUE #19 IS NOT COSMETIC -- IT IS A DATA RACE WITH A HARD CRASH. `IcosahedralFaces._ensure_built()` (core/frame/math/icosahedral_faces.gd) used a non-atomic lazy init (`if _built: return` ... build ... `_built = true`) over SHARED `static var` books. The terrain streamer derives faces on worker threads (globe_terrain_streamer._mesh_derive_job / _prop_derive_job), and several can reach `face_center()` before the first build finishes; two threads then BOTH ran the build and appended to the shared `_face_centers`, growing it past 20 (`Out of bounds get index '46'`) and tearing the heap (`malloc(): unaligned tcache chunk detected`, abort 134). On this repo's contended 2-core sandbox the crash reproduced on demand (16 threads calling terrain statics cold); on a normal host the derives finish fast enough that the race usually loses, which is why it read as boot "noise". FIX: a `static var _build_lock := Mutex.new()` guarding a double-checked build -- `_ensure_built()` locks, re-checks `_built`, runs `_build_locked()` (the old body, minus its trailing `_built = true`), then sets `_built` and unlocks. VERIFY: the 16-thread cold repro is 0 errors / exit 0 (was abort 134); probe_terrain_backend 11/0 and probe_stream_continent_a all-PASS, still exit 0. This is COMPLEMENTARY to the terrain-fence round's `async_shutdown()` (commit 1e00d88): the fence joins/drops workers at world death (the teardown-lifetime half), while this lock stops the two-lane build itself from tearing the heap mid-run. The fence's instrumentation falsified the race hypothesis because the window is timing-dependent -- the 16-thread cold repro (16 threads calling terrain statics before any build) still aborts 134 on the fenced HEAD, and passes under this lock. RESIDUAL (separate, still open on #19): the teardown-lifetime errors (`get_ticks_msec on a null value`, empty-name calls, "Thread object destroyed without its completion realized") are the probe/world quitting while a derive lane is mid-flight; a blocking `_exit_tree` drain DEADLOCKS on the slow sandbox (derives take 25-30 s there) so it was NOT shipped -- the remaining fix is a non-blocking drain (await frames until `pending_derive()==0`), left for a dedicated round. GATES: repro exit 0 / 0 errors, terrain probes exit 0, lint syntax 7/0 + indentation 5/0 + general 12/0 + charset 3/0 + autoload 9/0, test_terrain_determinism exit 0.
> **Last updated 2026-11-03 (PR-22 merge round):** OPENHANDS' QUEST/DIALOG/MONEY-LOOP SUPER-MERGE LANDED (branch merge commit `bf70f22`, PR #22 recorded merged): the playthrough driver walks 14 verified stages now and the branch also auto-closes #23/#25/#26/#27/#28/#29/#30/#31/#33 -- the big beds: QuestService rewards PAY (both authoring forms; faction/reputation routes through FactionManager.modify_reputation; quest chains enforce prerequisites via a shared `_first_unmet_prereq()`; optional objectives stop gating completion; `auto_complete` turns the onboarding quest in on the spot), DialogService's actions route the REAL seams (`STOP_FOLLOW`/`UNLOCK_TITLE`/`TEACH_SKILL`/`GIVE_ITEM`/`GIVE_CURRENCY`/`SET_WAYPOINT` etc. -- the dialog lane finally executes, set_waypoint reaches the real ZoneManager API), InventoryService grew the signed-delta `modify_gold` (vault + death gold-penalty stop no-oping), VendorService buyback is typed + persisted, TradeService's unique-item guard actually runs, corpse bag drop + the target ring mesh fix, QuestUI renders readable objectives (the `_esc()` BBCode double-escape bug), the journal's Complete tab keeps REWARDED quests, and the runtime nonexistent-method callers (CoordinatorService `GameLog.warning`, AutoResponseService kick/ban legs, HudIntegrator friend names) were routed to the real ones thru. THREE NEW default-lane receipts (not in the runner DEFAULT_SET, driven by web-ci + their own legs): test_dialogue_quest_reward 22/0, test_quest_availability 12/0, test_dialogue_ui_flow 7/0, plus test_trade_unique_guard 4/0 -- the driver is 77/0 and CI green at every commit. MERGE-INTEGRITY GATES ON MERGED MAIN IN THIS WORKTREE: lint `bash tests/lint/run_all.sh` 36/0 (the fence + character-panel gates unchanged), full pipeline `sh ./scripts/godot_test_runner.sh` exit 0 / **102 passed / 0 failed / 0 SCRIPT ERROR** with `playthrough_driver` + `test_quest_availability` + `probe_character_panel` + the four continent shards + `probe_planet_rebase_20km` + `probe_terrain_backend` all passing under the #19 fence (the pipeline ran TWICE to completion: pre-merge at 1e00d88 and post-merge at bf70f22 -- both 102/0/zero script errors; one aborted at 49 passes and one at 51 by the cloud runner restart, never by code). OPEN: #34 (PlayerManager roster API), #35 (NetworkManager client-message dispatch), issue #28/30/31/33 auto-closed by the merge. Next due: the S14.7 Sundered Sea content pass (the long lane), OpenHands now on 23/24-adjacent lanes.
> **Last updated 2026-11-03 (terrain-fence round):** ISSUE #19 CLOSED AS OWNER -- the teardown stderr spam ("Nonexistent function '_tint_for_pure' in base 'RefCounted (globe_terrain_streamer.gd)'" / "Nonexistent function '' in base 'Vector3'" / "Cannot call 'get_ticks_msec' on a null value" + Godot's "A Thread object is being destroyed without its completion having been realized") was TRACED, not believed: HEAD control runs (fix stashed) reproduce the exact 6 SCRIPT ERROR + 3 thread-warning spam on probe_stream_continent_a's natural exit, and the spam lands AFTER "TickService: Stopped" -- THE DERIVE WORKERS ARE STILL RUNNING when the engine starts finalizing (the empty '' names are calls resuming into script state the finalizer frees around them; the get_ticks_msec-on-null is the Time singleton dying mid-call). THE ISSUE'S OWN HYPOTHESIS (a) WAS FALSIFIED BY INSTRUMENTATION: the statics are politely resolved (23 mesh jobs / 11 prop jobs entered and completed inside the workers in one instrumented boot) -- the killers are the UNJOINED THREADS at world death, the exact mechanism probe_meshcache_ram already works around with its clean-exit drain. DEBUG-INSTRUMENTED proof chain: fence entered at world death with N live workers; normal jobs join instantly; a straggler class of RE-DERIVE jobs (face re-kicks from the final frames) parks mid-compute in an engine-internal futex (all worker threads observed parked at futex_wait with ~0% CPU while main lived) and NEVER resumes except under the finalizer -- unbounded wait_to_finish() on it hangs the exit FOREVER (three 900 s timeouts), so THE BOUNDED LAW is the fence's spine: `globe_terrain_streamer.async_shutdown()` (MAIN THREAD ONLY: kickers + appliers are main-thread) marks the streamer closed, then joins every worker that finishes inside a 30 s window -- `wait_to_finish()` only on threads whose job RETURNED (a fast reap), a still-alive park past the window is DROPPED (its Thread dies unjoined, the one honest residue the finalizer would hold anyway) instead of wedging the boot -- then the mesh+prop books clear under their own mutexes. `_kick_mesh_derivation`/`_kick_prop_derivation` refuse work after the fence (`_shutdown` guard -- a dying world never feeds new doomed jobs). `globe_world.gd` grew `_exit_tree()` -> the fence (guarded `has_method`, mock/fence-less streamers stay silent); every world death -- scene swap, probe exit, teardown -- walks the fence BEFORE the node releases the workers' script state. MEASURED vs HEAD control (7 boots / 4 boots): drained boots (probe_planet_rebase_20km, probe_terrain_backend light-load, meshcache) 0 SCRIPT ERROR / 0 thread warnings both sides-per-fence; straggler boots (continent_a, terrain_backend under heavy host contention): 6+3 at HEAD -> 0-3 + 0-3 fenced, and the exit is GUARANTEED natural (HEAD had no exit risk; the fence never adds one -- the bounded drop). RECIDIVISM NOTE IN EAR: the straggler park is ENGINE-LEVEL (issue's own suggestion (b)) -- a 4.7.2 parked-mid-derive worker only resumes inside the finalizer; this round does NOT fake that away, it bounds the cost so logs in the normal and drained cases are silent and no boot can hang. Lint 36/0; full pipeline gate in this round's entry below.

> **Last updated 2026-11-03 (character-panel live stats round):** ISSUE #21 CLOSED -- the character panel reads the character AS THEY ARE, not as they were born: `character_panel.gd`'s `_refresh_stats_display` now renders LIVE truth -- the header and every stat total ride the LIVE level (`_get_local_player()`'s `level` when the body carries one, else the book's), totals come from the new `CharacterData.get_stat_total(stat_name, level_override=-1)` (the +5 sky-blessing law stays INSIDE get_stat_total -- no forked math), the gear delta is read straight off the live bag `_resolve_inventory().get_equipment_stats()` (the SAME book `_apply_equipment_stats` pushes onto the player, single source of truth, parallel write forbidden), and the derived rows route the SAME merged book through the new `CharacterData.get_derived_stats(stats_override={})` (empty = old behavior; the override carries ALL SIX keys because get_derived_stats pads missing keys at 10 -- dropping an untouched stat would silently rewrite it to the floor). Card display law: allocated + gear both -> "%d (+%d pts, +%d gear)", gear only -> "%d (+%d gear)", allocated only -> "%d (+%d)", else plain total. Refresh hooks: `_show_tab` re-renders stats/skills on the STATS/SKILLS shows, and `_equip_item_from_picker` + `_unequip_item` call refresh_stats() after the equipment grid re-render. THREE DEAD-AT-BIRTH LEGS the receipt surfaced and killed: (1) the equip picker + its apply handler iterated `inv._items` -- NEVER a member; the store is the index-addressed `_inventory` -- so every slot picker said "No equippable items" forever and the apply leg always fell to "Could not find item in inventory"; both now walk `_inventory`'s indices. (2) The stat value lookup `VBox/Value` named a node that was a GRANDCHILD (card > HBox > VBox > Value, the HBox auto-named) -- the lookup missed on every resolve, so the six stat value labels froze at their birth text for the panel's whole life; HBox is now named and the lookup is `HBox/VBox/Value`. (3) The tab never re-rendered on show or on equip/unequip -- the hooks above. RECEIPT: `tests/probe_character_panel.gd` EXTENDED in place (runner DEFAULT_SET -- modified, not added, no fleet-pack regen) with the LIVE-TRUTH leg group E beside its original A-D: the level law (book totals at LIVE 7 outrun the stale creation-time cd.level=1), real gear through a REAL bag (wep_iron_sword +5 strength, acc_ring_first_light +2 vitality, equipped from their ACTUAL bag slots -- `add_item` stores a DUPLICATE, so the receipt matches by item id, never resource identity), the header's "Level 7" printed over a cd.level that still says 1, the strength card exactly `"%d (+5 gear)"` from the level-aware total + bag delta, and derived max_health equal to `get_derived_stats(merged_expect)` -- expected value computed by the same method, formula shorts never forked. Exit 0, 24 checks / 0 misses, 0 SCRIPT ERROR. Receipt-lore: the probe's `_check` grew an optional fail-detail third arg (same shape the world probes use); InventoryService-keyed bags resolve through the documented register/pull pattern. GATES: probe exit 0 24/0, lint 36/0, full pipeline exit 0 / 102 passed / 0 failed / 0 SCRIPT ERROR. Next due: OpenHands' dialogue/quest lane stays clear; issue #19 remains open/cosmetic.
> **Last updated 2026-11-03 (money-hub world-building round):** THE SIGIL SINKS GOT A PHYSICAL HOME -- the Concord pillar shrine boots in Nexus Central's capitol plaza at bearing -95: village_props.gd gained the `concord_shrine` kind on CAPITOL_BATCH (dais + 5 m pillar + sky-cyan emissive TorusMesh sigil band, emission 1.2 + bronze capstone + OmniLight halo, deferred in-tree PropCollider.attach via lambda) and a CAPITOL_NPC_BATCH row (-95/+0.006) + zone_nexus_central roster entry spawn the CONCORD HERALD (data/npc/npc_concord_herald.tres NPCData, merchant_general.tscn scene, `npc_type` omitted -- not declared in npc_data.gd, orphaned dead data in old .tres files) whose offering ref data/npc_offerings/concord_pillar_vault.tres (NPCOffering -> PremiumShopService, panel premium, mirroring black_market_premium.tres) rides the EXISTING offering plumbing -- the "Sigil Vault" action menu + "[E] Open Sigil Vault" prompt mint themselves with zero service changes (verified action_menu.gd/npc_entity.gd seams). RECEIPT dev_temp/probes/concord_shrine_probe.gd (dev_temp only, NOT in runner DEFAULT_SET -- world-building precedent, no fleet-pack regen) exit 0 SHRINE-OK 14 passes / 0 misses: data doors (herald loads, offering ref, premium route, roster+batch rows), a REAL globe boot placement leg (ConcordSinkShrine node + herald entity carrying npc_data.id), and the factory body/glow laws (PropBody BoxShape pillar tall > 4.5, the band's emissive TorusMesh + the halo OmniLight found). NOISE VERDICT SETTLED by HEAD control stash cycles with the fixed probe: the intermittent boot SCRIPT ERRORs (sector_cache set_value/get_value, get_ticks_msec on null, "Nonexistent function '' in base 'Vector3'") appear IDENTICALLY at HEAD (same classes, 4 lines) -- pre-existing globe boot randomness, NOT this round; the probe gates on its own verdict only. probe_starter_village stale eliminations refreshed: the capitol prop family is 4 (ConcordSinkShrine joins ankh/moon gate/bout stones) and the capitol roster counts >= 8 incl. the herald. GATES: probe exit 0, lint 36/0, full pipeline exit 0 / 102 passed / 0 failed / 0 SCRIPT ERROR. Next due: issue #21 (stale character-panel stats), then OpenHands' dialogue/quest lane stays clear.
> **Last updated 2026-11-02 (sigil-sink round):** THE CONCORD SINK CATALOG SHIPPED -- the vault panel's far half: BEFORE this round a Concord Sigil could enter a wallet (SKUs through the webhook armor at `a571019`, the gamble's refund-fail books) but could not LEAVE for anything but a black market roll -- no honest OUT door existed, so the SKUs sold an open loop. core/services/sigil_sink_service.gd (the PremiumShopService dialect; static singleton(), NO autoload wiring) declares SEVEN real sinks priced against the processor ladder (sigil_100 = $4.99): FIVE steed deeds riding RideService's real persisted ownership book (data/mounts truth, VENDOR source only, Meadow Pacer 150 / Plains Runner 250 / Reef Glider 400 / Trench Wyrm 650 / Storm Lancer 900; the GM Skywarden's wyrd * is refused ONE GATE BEFORE the service's own fail-closed so the buyer never gets within a debit) + TWO new premium title editions in data/titles/ (title_pillarsworn.tres + title_deepseabaron.tres, UnlockMethod.PURCHASE -- the schema value existed at birth and now earns its grant leg; they equip through TitleService's real register/equip surface) at 200/500. THE BOOK LAW = the audit talks hold: GATE BEFORE BOOKS (unknown ids refuse BY NAME; already-owned reads the REAL books; exact-need affordability; QoS rate gate) then debit-once, grant-once, and a REFUSED GRANT LEG REFUNDS EVERY SIGIL (a refund that cannot land is a hard GL.error -- books never keep a sigil without the prize). GL.info audit line per sale; one sink_purchased signal with the panel as its consumer (no-void law honored). RECEIPT tests/test_sigil_sink_catalog.gd exit 0 six legs: catalog truth (no phantom ids, no GM price), unknown/wallet-less/broke refusals by name, exactly-150 Pacer into RideService.owns_mount + dupe refused without a second debit, exactly-200 Pillarsworn + REAL equip surface, the refund law on both legs via injected refusing doors on a FRESH instance (the transport-receipt seam: injectable resolvers, never product fakes), and the voice + panel render. PremiumShopUI grew the "Where sigils go" section (owned state rendered from the real books, disabled owned rows, hashed dedupe toasts). SCRIPT-MODE LAW EXTENDED IN EAR: TitleService has NO class_name -- bare static calls (TitleService.unlock(...)) do not compile in --script/--check-only context at ALL; route through the autoload NODE calling the instance impls the static facade wraps. Open lanes: OpenHands' play drivers (landed PR #20 as 315d607; dialogue/quest systems next), issue #21 (stale character-panel stats) folds into a pricing round. Next due: Concord money-hub world-building (the physical home of the sinks).
> **Last updated 2026-11-02 (PR-20 merge round):** OPENHANDS' PLAYTHROUGH DRIVER LANDED (repo PR #20, merge commit 315d607): a headless+rendered driver (tests/playthrough_driver.gd + node runner, node-runner law) that walks the REAL input pipeline on world_playable -- spawn -> F2 target a live wolf -> attack to death -> interact-collect the corpse -> equip wep_iron_sword -> blacksmith repair -> NPC menu -- asserting on LIVE nodes, plus the six bugs it surfaced: (1/2) equipment stats never applied to the player (parent read as typed Entity aborted the apply; bonus re-add had no inverse so re-equip stacked) -- duck-typed stat surface + idempotent deltas + Entity-parity get/set/add_stat on PlayerController; (3) currency-only loot rolls were dropped by the item-only gate; (4) the INFINITE-GOLD PICKUP EXPLOIT (a currency-only ground drop was never consumed on pay) -- consumed-on-pay + test_ground_loot regression; (5) the TargetFrame resolved its id as entity_id and HID ITSELF for the whole game -- id normalization + render-on-acquisition; (6) respawn crashed near NPCs without health_component and the dungeon portal registered a phantom "teleport" schema. Runner DEFAULT_SET is now 102 tests. GATES: pipeline exit 0 (102 passed / 0 failed / zero script errors), lint 36/0. PR #18 closed landed-not-merged (e1f49bc); OPEN: issue #19 (terrain worker-lane stderr resolution race, cosmetic) and issue #21 (character panel reads stale creation-time CharacterData instead of the live gear-adjusted player stats -- fold into the sigil-sink/pricing round). Next due: sigil-sink catalog.
> **Last updated 2026-11-02 (webhook transport round):** THE PAYMENT WEBHOOK TRANSPORT SHIPPED -- the processor's HTTP entry finally has an engine on the other side of the door (before this: `handle_webhook` consumed ZERO deliveries through any real burden -- the armor answered to silence, no GL audit line ever described a payload, and the SKUs sat behind a wall between customer and wallet). THE BRIDGE half (srv/webhook-bridge/, mirrors srv/redis-bridge/ exactly: main.py entry + server.py routes + backends.py inmemory/redis + its own stdlib test suite, port 8083): nginx routes PUBLIC /hooks/<channel> in BOTH http+https server blocks to 127.0.0.1:8083 (own hooks zone 5r/s burst 20, 64k body cap); the sidecar accepts the processor's POST (202 accept-first, 413 over cap rejected BEFORE storing, 503 queue saturated), stores the delivery VERBATIM (raw body bytes base64 -- never re-serialized; headers lowercased + hop-by-hop stripped + dupes ","-joined; the SIGNATURE HEADER TRAVELS untouched), and hands each delivery to the engine poller: GET /deliveries/next claims the oldest claimable (secret-free claim token, per-claim TTL default 120 s -- a dead poller's claim lapses and the delivery reopens, at-least-once transport law), POST /deliveries/<id>/ack records the engine's VERDICT (processed|refused|expired|error, detail <=256 ch; stale/mismatched claim -> 409, delivered-since -> 200 idempotent "already", unknown id -> 404), delivered records STAY as operator audit; GET /deliveries/<id> + /stats are the operator readout; GET /health. THE SECRET LAW: the bridge holds NO HMAC secret and verifies NOTHING -- transport, not armor; PAYMENT_WEBHOOK_SECRET stays in the ENGINE process env and the provider revalidates everything. THE ENGINE POLLER (game/core/economy/webhook_transport.gd, no class_name; booted by NetworkManager._boot_webhook_transport in the prod/server start path ONLY when WEBHOOK_BRIDGE_URL is in the env -- OFF is an honest boot state, clients and dev bots never poll): HTTPRequest legs poll /deliveries/next on a Timer (default 5 s, configure() seam, one request in flight via _busy), feeds the provider board's handle_webhook(RAW bytes, headers) -- the provider resolved through PremiumShopService's registry resolver (injectable resolver for script-mode receipts, runtime load() only, no parse-time preloads) -- and acks the verdict. THE ONCE LAW lives in the engine: a per-process ledger (_handled: delivery_id -> verdict) refuses to re-run the door for a resolved id; a redelivery re-acks the FIRST verdict; NOT call counting on the provider -- the book of record. EVERY deliver_once exit settles BEFORE it answers (ledger writes, then verdict travels: no re-entrant beat can double-run the door). REFUSALS ARE ANSWERS: a refused delivery still acks (a refusal that never acked would replay-wrap forever); verdicts: door complete->processed (order poll leg pays), refused->refused (the armor's own reason rides the record), cancelled->expired, wrong channel->refused unrouted (PAYMENT_WEBHOOK_PROVIDER env is the channel map), provider missing->refused no-provider; transport legs (poll/ack network) retry on the next tick fail-soft. The bridge Python suite (14 tests: FIFO + claim exclusivity, TTL lap-over, ack contract incl. already/unknown, id uniqueness, verbatim bytes round-trip; HTTP: health, the accept->next->ack happy path with signature-header-survives, 413, verdict allowlist, claim-mismatch 409, null views) AND the engine receipt tests/test_webhook_transport.gd (boot law OFF/ON, 5 s default + configure seam, signed-truth delivery routes the door EXACTLY once through the RAW-byte path and pays 100 through the poll leg into a mounted wallet, redelivery re-answers from the ledger, unsigned dies AND settles so a replay cannot wedge, wrong-channel/no-provider refuse by name and settle, a mixed-case signature header survives the normalization and still honors the armor) both exit 0. entrypoint.sh starts the bridge in TEST mode (with its unit suite added to the CI bridge gauntlet) and PROD mode (127.0.0.1:8083, first free port after noaa 8082). DEPLOY.md services table + health list updated. Next due: sigil-sink catalog + OpenHands' staging PRs (gameplay driver A, crafting leg B, perf honesty C).
> **Last updated 2026-11-02 (PR-18 verified round):** OPENHANDS' ANALYSIS ROUND (PR #18, branch fix/terrain-stream-probe-surface) was VERIFIED IN THIS WORKTREE AND LANDED ON MAIN: three REAL product bugs + five stale test assertions -- (1) `cosmic_rng.stir_from_cosmic` read `total_chaos` as a property but it is an ACCESSOR METHOD (CosmicEntropy.total_chaos()), so every stir threw "Nonexistent 'int' constructor" and silently DROPPED the chaos entropy word -- two skies with equal kp but different accumulated chaos produced IDENTICAL streams; now calls the accessor guarded by has_method, and the co-located test_cosmic_rng.gd mirror call is fixed too (the audit's seam: a wrong read that QUITS quietly had made an entropy input decorative).

> The rest of the round: (2) inventory_service.get_inventory returned FREED InventoryComponent entries as a typed value -- "previously freed instance" at every consumer; now is_instance_valid=false drops the stale row and returns null (absent keys erase harmlessly). (3) hud_integrator._bind_player_wallet_feedback read player.gold_changed unconditionally -- the globe body (GlobeWorldPlayer) declares no gold/gold_changed (its purse is the mounted component), so every globe boot logged "Invalid access to property or key 'gold_changed'" and the node-wallet leg never bound; has_signal guards on BOTH legs. (4) the runner's DEFAULT_SET/LONG_TESTS were word-split unquoted with comment lines -- comment words became phantom test names and one empty token made grep -qx match EVERY line (long timeout for all); the lists are stripped of comments/blanks before iterating. (5-8) STALE ASSERTIONS against the shipped world: the four probe_stream_continent shards pinned get_surface_count() == 2 but the streamer legitimately emits 3 (ground+skirt+hydrology water; the >=2 form probe_terrain_planet already uses); probe_thermals pinned 7 updrafts while data/thermals grew to 10 (8 thermal + 2 launcher); probe_planet_rebase_20km read streaming face counts before the async derives drained (now drains pending_derive first, the continent-shard law); globe_driver_runner pinned a fixed ride-height from the 100 m prototype era, misreading a correctly seated 20 km world body (28 m spawn plateau, off_shell_29.52) -- now asks the body is_glued(2.0) like probe_planet_walk_20km. VERIFICATION GATES in this sandbox on the applied branch: full pipeline `sh ./scripts/godot_test_runner.sh` exit 0, 101 passed / 0 failed / 0 phantom / 0 SCRIPT ERROR (the previous restore's continent/crafting/thermal probe fails are GONE -- they were the code bugs above, not import-cache drift as once suspected); lint 36/0; naming exit 0; receipts cosmic 8 PASS legs, thermals 10-PASS form, gamble 9 legs, premium 6 legs all exit 0; parse checks on every touched file exit 0 (inventory/hud files check-ONLY "Identifier not found" is the documented script-mode autoload artifact, identical pre/post-patch). NOTE: the earlier 'partial .godot import cache' hypothesis for these probe failures is RETIRED -- PR #18's code fixes account for every failure. Next due: old transport (webhook HTTP entry) + sigil-sink catalog.
> **Last updated 2026-11-02 (economy audit round):** THE AUDIT SWEEP ACROSS THE FRESH ECONOMY SURFACES (black market gamble + webhook armor + premium seam + Sigil Vault panel) FIXED FOUR BOOK-SAFETY BUGS AND TIGHTENED THE ARMOR. (1) THE QUANTITY TRUTH: the gamble drew its QUANTITY REPORT after the GRANT -- a min1/max3 band could land x1 in the bag and say x3 in the toast; the band is now rolled ONCE inside the draw (`_draw_shape`) and grant/report/audit/toast all read that single number, with corrupt band data (min > max) clamp-refused instead of taken through randi_range (a bad range aborts a function -- past the debit that would strand sigils without the refund leg). (2) NEVER BURY A PAID ORDER: the service poll CLOSED the order BEFORE the grant -- a failed grant (wallet unmounted at the moment of truth) erased a genuinely-paid checkout with zero recourse; now grant-before-close: a failed grant leaves the order OPEN and the next poll re-attempts (providers keep reporting complete for a paid order); the residual crash window between grant and close errs CREDIT-side. (3) CANCEL NEVER BURIES MONEY: provider.cancel flipped a COMPLETED (paid) order to cancelled -- webhook AND manual both; a buyer could cancel a paid checkout out from under itself; both providers now REFUSE cancelling a completed order and the service honors the refusal (returns it, keeps the order open) so the poll leg pays instead. (4) PROVIDER HALF OF THE REBOOT LAW: the webhook provider's own pending-vs-paid book lived in RAM, so a rebooted process refused a genuinely-paid webhook; order records now ride the DictStore KV door (`premium:webhookorder:` prefix -- hydrate in _init, written at birth and on every state move; completed/cancelled records STAY so duplicate deliveries stay honestly refused after a reboot) and begin ids loop-until-unique (a collision could silently overwrite a standing order). TIGHTENED: the HMAC chain no longer SKIPS on an empty derived signature (refuses, fail closed); sigils are priced INTO the open order at begin time (a later catalog edit can never change what a paid order grants); panel toast dedupe keys carry the message hash (the fixed key let the 5s window swallow the next honest answer) and a dead `ok` var left the vault. Receipt legs added: cancel-refused paid order pays through poll (exactly 100), grant failure keeps the order open and the retry pays exactly 100, a fresh provider refuses duplicate delivery after reboot. Parse-law note AGAIN: `max()` is a Variant builtin -- `var lo := max(...)` is a PARSE ERROR under warnings-as-errors (`var lo: int = max(...)`). Pipeline note: the full runner in this restored sandbox exits 1 on PRE-EXISTING probe failures (stream continents a-d crash cascade, crafting, thermals prefix taxonomy -- world/streamer derive chain, probes age Oct 18, reproduced at the pushed HEAD with this round stashed; suspected partial `.godot` import cache after the restore) -- the touched surfaces' receipts (gamble 9 legs ALL-OK, premium 6 legs ALL-OK, economy) ran INSIDE that pipeline green. Gates: gamble receipt exit 9 legs, premium receipt exit 0, lint 36/0, naming exit 0.
> **Last updated 2026-11-01 (black market gamble round):** THE FIXER IS A GAMBLER NOW. THE DEEP ROLLS: BlackMarketService (the PremiumShopService singleton dialect) is the gamble engine -- roll_deep(player under their purse, roll_id) debits HONEST sigils from the ONE purse and lands ONE weighted draw out of a REAL LootTable; the pools are data/loot_tables/loot_black_market_tide.tres (3 sigils, the shallow wash) + loot_black_market_depths.tres (12 sigils, the pressure where the rare gear dreams) -- the same LootTable schema the wolves use, so as higher-tier weapons/armors arrive the pools grow by APPENDING ENTRIES (documented shape, no code change; the receipt refuses phantom SKUs). Two tiers with rarity_boost (the depths pays UP); draw math is pure server truth -- the panel/client sends only a roll_id, never weights, item ids or amounts; the prize grant rides inv.add_item via DataService truth and a FAILED grant REFUNDS the sigils (refund-fail is a hard GL.error -- the books never keep a sigil without paying the prize); every completed roll emits roll_granted + GL.info audit line. GATES BEFORE BOOKS: no wallet / broke (names the exact need) / unknown tier / QoS rate_limit("black_market_roll") BEFORE any debit leg moves. THE WEBHOOK ARMOR (defense in depth, core/economy/webhook_payment_provider.gd): the hosted-checkout adapter every real processor slot inherits -- (1) secret zero-knowledge: HMAC secret read from env PAYMENT_WEBHOOK_SECRET on every verification, never in the repo, and an EMPTY secret refuses everything (fail closed); (2) HMAC-SHA256 over the RAW payload bytes, signature envelope in the x-synmergia-signature header ("t=<ts>,v1=<hex>"); (3) freshness -- 5-minute signed-timestamp window kills transcript replay; (4) order binding -- the payload's purchase_id must name a PENDING order the provider itself opened for that buyer; the caller never supplies player identity or amounts; (5) server-side accounting -- sigils come from the provider's own catalog, never the payload; (6) idempotence -- an order completes ONCE, duplicates report already-processed honestly. The transport must call handle_webhook(RAW bytes, headers) once per delivery; the SERVICE grant then re-validates kind/sigils itself, so even a compromised processor truth cannot inflate the purse. THREE HOSTED SKUs ride the provider (100/280/650 sigil packs). REBOOT LAW: PremiumShopService open orders now ride the DictStore KV door ("premium:order:" prefix, chat-book pattern) -- hydrate in _init, persist on open, erase on close, so a checkout mid-flight survives a process restart and can still be fulfilled honestly after; adapters are re-registered at boot (plugins live at boot, not in the KV). THE PANEL: PremiumShopUI grew the Deep Rolls section under the SKU rows (roll rows with cost + pool description tooltips, one Roll button per tier, roll results toast through the NotificationService CUSTOM lane, refresh rides the service's own roll_granted). Receipt tests/test_black_market_gamble.gd exit 0 six legs (pools real/no phantom SKUs, gate refusals by name, 100 sigils in through the honest seam then the golden pull pays one real item and debits exactly 3, rate gate leg, webhook armor chain unsigned/tampered/stale/foreign die + signed-truth grants 280 exactly once + dupes refused + closed polls none, reboot hydrate/erase round-trip). Receipt-lore: a fresh service instance builds its own provider board and must RE-register adapters (the receipt does this before its checkout -- which is also what a rebooted process does). parse-law notes: extends by RES path for the provider chain; var limit: int = max(...) because max() is a untyped builtin (inference from Variant is a parse ERROR under warnings-as-errors); DictStore all_keys/get_value/erase is the KV door. Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, all receipts exit 0.
> **Last updated 2026-11-01 (true-void survivors round):** THE TRUE-VOID LIST CLOSED. THE THREAT SENSE shipped as the enemy/threat-telemetry consumer: hud_integrator._bind_enemy_threat_sense (deferred in _connect_all, once-guarded) joins SpawnService.enemy_spawned and, per spawned enemy, binds its AggroComponent legs -- target_changed rows 'The Wolf turns its attention on you.' on a flip ONTO the local player and 'You slip out of the Wolf's attention.' off, threat_overflow (its FIRST HONEST EMIT, at AggroComponent.add_threat's clamp leg, exactly once when a source's threat first crosses max_threat_per_target) rows 'Your threat on the X maxes out.' (only when the source IS the local player), out_of_combat rows 'The X forgets the fight and breaks off.' through a small _enemy_focused_local book; stranger flips stay silent. threat_changed was REMOVED (decl+3 emits: every leg it covered is a target flip or an overflow; the per-hit number spoke to zero listeners for life). THE ZONE TRIO got its consumer: InstanceService._ready subscribes ZoneManager.instance_created/instance_destroyed -> _rebuild_arena_registry -- the instanced-zone registry was rebuilt ONCE at boot while ZoneManager emitted into silence, so live creates left is_instanced_zone stale until the next boot; the subscription fixes the staleness bug and consumes both emits; instance_contract_changed was REMOVED (a zone contract is boot-static -- gravity/capacity/deadline read ZoneData with NO mutate path; re-declare WITH emit+consumer if hot mutation lands). REMOVED WITH CAUSES: SpawnService.npc_spawned (entity_spawned is the one spawn voice; minimap impressions ride it), NotificationService.notification_queued (queue legs already speak via notification_sent + history; the silent pop-oldest OVERFLOW now GameLog.warns), AgentConnector.observation_ready (the POST leg already lives in send_observation; no consumer ever existed). DRIVE-BY: the connector-native shadow law -- AgentConnector.connect/disconnect/is_connected, VantConnector + McpConnector connect/disconnect, and AgentAction.to_string() all overrode NATIVE Object methods (warnings treated as errors only surfaced when a receipt compiled the chain); renamed to connect_agent/disconnect_agent/is_agent_connected (+ 4 internal call legs, ConnectorService's two callers) and the un-called to_string debug-helper deleted. Receipt tests/test_true_void_survivors.gd exit 0 five legs (sense rows + stranger silence, overflow exactly-once at first cap crossing, removals hold incl. has_signal probes on four autoload scripts, fight-broken book leg, live zone registry rebuild; zero SCRIPT ERROR -- the chain compiles clean now). Receipt-lore: probe enemies need the tiny dynamic-script shape (a bare Node gains NO 'aggro_component' from set()). Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, all receipts exit 0.
> **Last updated 2026-11-01 (premium wallet round):** THE SPLIT-WALLET DEBT DIED AND THE REAL MONEY SEAM WAS BORN. THE ONE PURSE: InventoryComponent is THE authoritative per-player wallet -- its get_currency_amount/add_currency/remove_currency now understand the DEFAULT wallet ("" and "currency_gold" both route through the honest gold legs, others ride the _currencies ledger with the catalog gate + caps -- the split is storage, never semantics); PlayerController.gold became a SYNCED MIRROR (a property setter converts EVERY direct write -- progress restores, horde shares, dwelling field-math -- into REAL deltas through the purse, so nothing pays silently; add_gold delegates to the mounted component and the node stays silent; standalone bodies keep their own voice; the _ready adoption step resyncs the mirror from a boot-restored bag and connects the purse's gold_changed to the mirror). The hud binder keeps the node-seed leg for manual node emits (dwelling) and the component delta leg; the NEW leg binds comp.currency_changed into +N/-N <Currency display_name> rows (no seeding needed: restores never emit, every emit is a real movement; gold and zero-deltas stay quiet). PREMIUM CURRENCY: CurrencyKind.PREMIUM (kind 5) + data/currencies/currency_concord_sigil.tres (Concord Sigil, gold_per_unit 5000, soulbound, NEVER convertible -- it only enters a wallet through the payment seam). THE PAYMENT PLUGIN SEAM (core/economy/): PaymentProvider (RefCounted base; get_catalog/begin_purchase/poll_purchase/cancel; statuses pending/complete/cancelled/refused), ManualPaymentProvider (REAL checkout from the buyer side; money never moves automatically -- fulfill_purchase() is the operator seam a Stripe/Steam adapter replaces; statuses are read, never invented), PaymentProviderRegistry (board by id; re-registering an id REPLACES it = THE swap law; _init seeds the manual default), all owned by PremiumShopService.registry() so no static-call/global-cache parse quirks ever bite. PremiumShopService (singleton dialect like VendorService): renders the board catalog, opens/cancels orders, and grants sigils ONLY on a provider-reported complete through inv.add_currency(currency_concord_sigil, N) -- the ONE grant leg, validated against DataService's kind, closed once, poll after close honestly 'none'. THE UNDERDECK FIXER: npc_black_market_fixer.tres lives in Nexus Central's strand frame (globe_world CAPITOL_NPC_BATCH + zone roster), sells the ledger goods (acc_ring_first_light + acc_cloak_wanderer priced in SIGILS, item_ancient_coin/strait_charm/skiff_ticket in JUNKER SCRIPT) -- VendorService learned per-entry currency: catalog rows carry "currency" (_entry_currency scans the catalog_items entry), buy_item checks/affords/pays through the unified ledger with honest per-currency refuse messages; ShopUI quotes them ("40 Junker Scrip each (you have N, total M)"). THE PREMIUM VAULT PANEL: PremiumShopUI (UIPanel law, MenuManager "premium" row, service gate on PremiumShopService + walk-away close), opened from the fixer's action menu "Sigil Vault" or interact prompt [E] Open Sigil Vault; shows the live sigil balance off the ONE purse, the processor name, SKU rows, pending order state + cancel. THE BAG LEDGER STRIP: every held non-gold currency renders live in the bag header (comp.get_currency_ids through DataService display names) and the blacksmith/gold labels stay on the purse. Receipt tests/test_premium_shop_loop.gd exit 0 six legs (currency voice rows incl. the double-speak guard, ONE purse read/route/refuse, seam pending/refuse/operator-truth, one-time grant + closed order, sigil grant row, panel real-open lifecycle). Receipt-lore: receipt preloads compile BEFORE autoloads register -- runtime load() in the body (the combat-sense law). Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, premium + all prior receipts exit 0.
> **Last updated 2026-11-01 (economy round):** THE ECONOMY TRUE-VOID CLUSTER WAS A CENSUS ARTIFACT -- the real money machinery was never void, it was TWIN-VOICED AND INVISIBLE: two honest wallets move the local player's gold (the NODE wallet, PlayerController.gold, paid by kill rewards/ground loot/horde/dwellings; the COMPONENT wallet, the mounted InventoryComponent._gold, spent by vendors/blacksmith/vault/ferry/transfers) and each emitted gold_changed to essentially one consumer (blacksmith_ui). PlayerManager.gold stays the silent persistence mirror (documented; unchanged). SHIPPED THE WALLET LOOP: hud_integrator._bind_player_wallet_feedback (deferred, local-player seam, per-leg guards) binds BOTH wallets into CombatLog rows -- node wallet speaks in paid deltas with seen-total seeding (hydration re-emits stay quiet), component wallet rides its signed deltas (+N loot rows / -N system rows); the NEW item_equipped signal (item, slot_name: String, equipped: bool) earns its emit on the REAL endpoints (equip_item/unequip_item; clear_equipment_slot = full-loot strips are unequips the player sees), landing "You equip Iron Sword (off_hand)." rows; slot names derive from Item.EquipSlot.keys() (wep_iron_sword.tres really declares equip_slot = 8 = off_hand -- flagged, not changed). The open bag went money-live: InventoryUI's Gold label was stale through every spend; DRIVE-BY CAUGHT: inventory_ui._setup_header was BORN ORPHANED with zero callers -- the bag shipped with no title, NO close X, and the gold total never rendered; the call now sits at the end of _setup_panel. Receipt tests/test_economy_wallet_rows.gd exit 0 six legs (binder no-crash, dual-wallet seed through the local-player seam, hydration-quiet + +45 delta rows, vendor +50/-25 rows, equip/unequip/strip rows via wep_iron_sword through the REAL bag, open-bag label follows the wallet). Split-wallet debt persists by design (node gold and component gold are separate sums until a unification decision; rows are per-wallet honest, no fake unified display). The capture-layer names gold_gained/gold_spent/xp_gained/item_equipped remain DEAD in core/events/{entity,inventory}_events (hub-referenced diagnostics only). Script-mode lore: a bare Node gains NO properties from set() -- probe wallets declare them in a tiny dynamic script (signal + gold + inventory_component). Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, economy + combat-sense + login + map-ping + fresh-kit + ignore-book + channel-mute receipts all exit 0.
> **Last updated 2026-11-01 (combat-sense round):** A FRESH CENSUS (598 declared / 234 OK / 282 regex-VOID / 82 DEAD) PLUS A TRUE-VOID SCAN (265 names mention NOTHING beyond decl(+emit)) -- the connect regex is blind to name-keyed UI connect maps (leader_changed: party + guild UIs already consume it via map keys) so census VOID overcounts; the true-void survivors are the real wallpaper. SHIPPED THE CAST-SENSE LOOP: the local player's CombatComponent lifecycle (cast_started/cast_finished/channel_ended/combat_entered/combat_exited) emitted zero-listener since birth; hud_integrator._bind_player_combat_feedback (deferred, local_player seam, no-crash when absent) binds the five signals into CombatLog System-family rows ("You begin casting X" / "You finish casting X" / "You stop channeling X (interrupted)" / "You have entered/left combat"); player-local on purpose (enemies already surface via skill_hit/skill_resolved). TWO WALLS DEMOLISHED by the duplicate-voice law (a second announce lane with zero consumers only repeats the working one): chapter_recorded removed from ActsService (_announce_chapter already notifies; the Chronicle re-reads on open) and boss_spawned removed from SpawnService (the world-boss arrival already rides NotificationService's bridge over EventHub.entity_spawned -- metadata notification_enabled + scopes, empty scope defaults SERVER-WIDE on the spawn path). DRIVE-BY FIX: PlayerManager.set_local_player(null) crashed on the display-name duck-read -- clearing the slot is a legal state, guarded. Receipt tests/test_combat_sense_loop.gd exit 0 (binder no-op honest, lifecycle-row truth through the entries, the entity_spawned announce bridge proven connected). Remaining true-void clusters: economy gold/xp catalog ghosts, enemy/threat combat telemetry, zone instance trio, npc_spawned (entity_spawned covers it), observation_ready, instance_contract_changed, notification_queued. Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, combat-sense + login + map-ping + fresh-kit + ignore-book + channel-mute + daily + acts receipts all exit 0.
> **Last updated 2026-11-01 (channel mute round):** THE LAST UN-FAKED CONTRACT NAME GOT ITS FEATURE, NO DUMMY EMITS. channel_settings_changed is now the OWNER signal of a per-channel mute feature: mute = a RECEIVE-side filter (the viewer hides a channel's incoming live lines in their own view only; own sends ride the normal pipeline); System stays unmuteable (the game's error/announcement voice). ChatService gains set_channel_muted/is_channel_muted/get_muted_channels/channel_by_name; every real change emits channel_settings_changed AND persists through _persist_player_settings -- the _player_settings dict + chat:settings: KV key were declared+loaded at birth with NO writer (the born-dead twin of the ignore list), now the write leg is real. Named refusals mirror the ignore API (duplicate mute, unmute-when-not, protected System). Commands /mute <channel> //unmute <channel> //channels (the state board) ride the API; /muted now ALSO lists muted channels. ChannelSettingsUI panel (UIPanel shell law; catalog rows read the enum through the service instance; System last + protected; refreshes on the service's own signal -- no private re-read) mounts on MenuManager "channels" + chat header [Channels] funnel. ChatUI.add_message drops a muted channel's incoming lines under the same one-filter-covers-both routing the ignore law uses. Receipt tests/test_channel_mute_loop.gd exit 0 (emit truth, refusals, KV + fresh-service reboot round-trip, command legs, display filter, panel toggle-writes-what-it-displays). BUG CAUGHT: iterating an enum bare (for channel in Channel:) iterates the enum NAMES, not values -- channel_by_name + _cmd_channels + the _ready history init all tripped it (history had silently keyed _chat_history by "SAY".."EMOTE" since birth; now all three iterate Channel.values()). Receipt-lore: DictStore.erase() is the real method (not erase_value); queue_free twins refreshed rows for a frame -- row-state reads go through the children, latest wrapper wins. Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, ignore-book + map-ping + fresh-kit + login receipts all exit 0.
> **Last updated 2026-11-01 (cheap pair + ignore book):** THE CHEAP PAIR SHIPPED + THE IGNORE BOOK. (1) WAYPOINT PING: full-map clicks navigate now -- click ON a quest waypoint marker emits waypoint_clicked (the declared signal, zero emits until now) and hud reads WorldMap.last_waypoint_hit() synchronously for the label; canvas clicks emit map_clicked with a TRUE world position (spherical law inverts lat_lon_to_uv exactly -- the old _screen_to_world fabricated flat 8km coords); consumer = hud_integrator._route_map_ping -> WaypointService.create_waypoint ("Map Marker" / "Quest: <label>") + activate_waypoint (beacon + compass ride the service law); the service's own notify path answers rate-limit/cap/invalid. Receipt tests/test_map_ping_route.gd exit 0. (2) CHARACTER CONFIRMED + KIT GATE: character_select emits its signal on Enter World (both legs are creation paths); StarterKitService listens via a tree node_added relay and gates the grant: fresh-confirmed OR no saved progress earns the kit, returning characters STOP re-collecting it per boot (_granted_for was session-only = a per-boot double-grant bug). Receipt tests/test_character_fresh_kit.gd exit 0. (3) IGNORE BOOK: /ignore had zero persistence (list evaporated per reboot), zero UI, and the chat UI's star-match reported "Unknown command" for every service command. ChatService gains ignore_player/unignore_player/get_ignored_players/is_ignored_sender (named causes; id-or-name display matching), _ready calls the previously-dead _load_chat_state (KV revive), /ignore//unignore//muted ride the API, ChatUI's default branch passes through the service's command router DIRECTLY (send_message returns true for unknowns -- direct call keeps the feedback line), add_message drops blocked senders on BOTH chat surfaces (MenuManager feeds the same panel; optional viewer_id for script receipts); IgnoreBookUI (UIPanel shell, idempotent build) on MenuManager's "ignore" row; chat header [Ignore] button. channel_settings_changed STAYS contract surface (per-channel semantics = a channel-mute feature we do not fake). Receipt tests/test_ignore_book_loop.gd exit 0. (4) DRIVING FIX: waypoint/trade/admin called EntityService.get_entity_by_id which does NOT exist (real: get_entity) -- every waypoint activation crashed the proximity tick; all four call sites replaced. Gates: pipeline exit 0 zero script errors, lint 36/0, naming 25/0, all new receipts + login exit 0.
> **Last updated 2026-10-30 (consumer-side round):** THE NO-VOID LAW'S OTHER HALF shipped -- consumers first, then emits earn their keep. DAILIES ROLL AT MIDNIGHT EASTERN now (SignService.current_human_day_index; America/New_York, DST honored via the compiled US rule, the 2-hour sky day and the UTC day both UNTOUCHED on purpose -- Concord calendar/world seeds/ambience stay on current_day_index); test_daily_quest pins both midnight boundaries + spring-forward/fall-back one-second edges. THE SLOT SERVICE WAS NEVER PRINTABLE: slot_service.gd was flat-zero-indent FOR LIFE (4 commits, all flat, never parseable, never referenced -- every gate stayed green over an unloadable file); reindented to tabs + verified via load probe, and ContainerConfigData's static load() SHADOWED the builtin (recursive call, schema never compiled) -> renamed load_config(). THE CONTAINER LOOP IS LIVE: SlotService.open_container/close_container emit container_opened/closed (endpoint did not exist), ContainerUI is the MenuManager 'container' panel (idempotent synchronous content build; UIPanel standard shell), hud_integrator routes through MenuManager.open_menu with an is_showing-guarded close, receipt tests/test_slot_container_open.gd exit 0. CooldownService._process emits cooldown_tick per active cooldown and CooldownIndicator (built for it, tired to reverse-engineering RATE_LIMITED toasts) binds started/tick/ended with instant cancel-retire. InputManager finally hooks Input.joy_connection_changed (controller_disconnected had zero emitters since birth); both pair signals toast CONNECTION_QUALITY. ModeratorProgression's four badge tiers now announce through governance_ref -> _on_badges_gained -> badge_earned -> ACHIEVEMENT_UNLOCKED toasts (inner-class law: owner is passed in, not bare). PartyService.share_xp emits xp_shared (PartyUI refresh rides it); _apply_hit's whiff leg emits skill_missed and hud feeds CombatLog.log_miss (the miss row had zero callers). NOT FAKED (still contract surface): channel_settings_changed (ignore book has no listening UI), npc_spawned (minimap already covers NPC spawns via entity_spawned impressions), zone instance trio, attack_hit (redundant with skill_hit/skill_resolved), observation_ready, instance_contract_changed, notification_queued, character_confirmed, waypoint_clicked. Event-catalog forensics: the deleted 4 files were born 73f6da0 as parallel domain buses whose own commit migrated everything to EventHub instead -- no doc ever promised a later role; EventHub + per-service signals carry every live name. Gates: pipeline 27/0 zero script errors, lint 36/0, naming 25/0, daily/DST + container-loop + quest/login all exit 0.
> **Last updated 2026-10-30 (signal-backlog round):** REAL CENSUS (regex-blindspot-corrected twice): 680 signals = 259 OK / 335 VOID / 78 DEAD / 8 NEWIRE -- NOT 188; grep cannot see string-built emissions (_hub_emit) or name-keyed UI connect maps, so some rows are false. SHIPPED: the dead event-catalog layer (core/events/{combat,entity,inventory,system}_events.gd, ~66 signals, zero refs) DELETED -- EventHub is the one live hub; all true NEWIRE loops closed (target_updated fires on the ring's re-seat frame + target_type_changed on the type flip; blacksmith repair_failed/item_too_broken on every honest leg incl. the can_repair-unreachable bulk path; quest_failed when an IN_PROGRESS daily expires at the sky dawn + abandon refreshes the tracker; respawn_canceled when a revive wins the pending-timer race; InventoryUI item_selected on slot select); the trade anti-scam countdown went LIVE from dormant (both-confirmed used to complete instantly; now a re-fetch-every-beat 3s window ticks through trade_ui's listener); the guild invite loop was finished, not just wired (accept/decline/expire endpoints existed NOWHERE and guild_ui called get_pending_invites() which did not exist; _persist_invite indexed a dict keyed by invite_id with a player_id -- dead writes; new RECRUIT-tier accept path + 30s dual-family sweep emitting the *_expired signals); party_member_updated emits at join/leave/kick; server_manager kick now rides the real NetworkManager.kick_player_by_character_id chain; VantConnector._on_poll GETs /api/action with a busy guard (was a pass-stub). NO-VOID LAW: zero-listener signals are NOT emitted (that would just turn DEAD into VOID wallpaper) -- channel_settings_changed, cooldown_tick, container_opened (no open-endpoint exists), npc_spawned, zone instance trio, skill_missed, attack_hit, threat_overflow, item_bound, bag_locked, badge_earned, state_exited, controller pair, observation_ready, instance_contract_changed, xp_shared, character_confirmed, waypoint_clicked are logged contracts. Gates: pipeline 27/0 zero script errors, lint 36/0, naming 25/0, login/quest/loot all exit 0.
> **Last updated 2026-10-30 (unwired-loops crawl):** THE GUEST-CLICK NOISE WAS A LOG SEMANTICS BUG: login.gd logged press+dispatch as FAIL+OK per click; one honest log now ([OK] on dispatch, [FAIL] only on a real dead end). UNWIRED LOOPS CLOSED in playable: player-menu "report" now reaches PlayerReporter.submit_report (alerts + webhooks); trade add-item is a real ItemList picker (stack + rarity rows, callback-driven so cancel can not strand an await); VaultService GUILD/ACCOUNT resolution wired to GuildService/AccountService and close_vault's false vault_opened emit removed; QuestService min_level gate enforced (_get_player_level existed) and per-player load/save rides the boot loader's DictStore KV path (db stubs deleted). BACKLOG: 188 service signals never fire and/or have zero listeners (telemetry wallpaper, multi-round); vant GET + NetworkManager.disconnect are server-infra TODOs. Pipeline 27/0 exit 0 zero script errors, lint 36/0, naming 25/0, quest gates exit 0.
> **Last updated 2026-10-30 (targeting crawl + ring tracker):** TARGETING IS FULLY HOOKED (crawl): SpawnService registers/unregisters every spawn, Tab/F2/click/interact-press all route through the one `TargetingManager.set_target` chain, HUD TargetFrame/boss bar bind `target_acquired/cleared/updated`, tooltips + party click-targets + a11y ride the same chain, and `use_skill` casts at `get_current_target().node`. THE RING: the pulsing emissive circle mesh under the current target now TRACKS MOVING TARGETS (`TargetingManager._process` re-seats it from the live node; nothing else ever updated it -- zero callers on `update_targetable_position`/`update_highlight`). PIPELINE IS FULLY GREEN HEADLESS: 27/0 exit 0 -- the "pre-existing" 2 failures were schedule drift (the async world boot registers the player ~2 s late), now `_await_player`-gated with a live-NPC re-resolve, plus 3 ring checks (visible, seated under the NPC, hidden on clear).
> **Last updated 2026-10-30 (target-action loop):** THE TARGET-ACTION LOOP SHIPPED: E / touch ACT button / left-click converge on `PlayerController._on_player_input("interact")` -> `_try_interact`, which now opens the ACTION MENU for the nearest NPC/gate in 6 m (`_try_target_context_interact` + `TargetingManager.get_nearest_targetable_by_types`): walk up -> press -> menu -> interact, with an in-range live Tab target outranking the nearest scan and the menu centered (no cursor). Ground loot stays first; placed stations/ankhs after. Receipt: `tests/test_interaction_pipeline.gd` async runner (waits for the async player registration) proves NPC menu (offering-filtered items), dungeon-gate Enter, and 40 m silence; the 2 pre-existing headless guest-click failures are unchanged (test's documented runner is xvfb-run).
> **Last updated 2026-10-27 (audit):** FUNCTIONAL AUDIT SHIPPED (`dev_temp/probes/render_audit.gd`, AUDIT-OK 42): the main world + the underworld booted through the real seams, every recent build walked and asserted on live nodes (beacon/guide halos + night law, Pans deck pieces, cistern, wilds, lake, trail, vents/thrower, mist, live swim credit + a real body's burn). AUDIT-CAUGHT FIX: the lava lake's first geometry sat BELOW the walk shell -- rebuilt to the cistern's walk-line dialect (basin slab collidered at 2000.0, melt surface 2001.2, curb 0.55 over; commons seats re-based, 18/18). Known script-mode noise: headless boots emit pre-existing derive-chain stderr (streamer tints/river specs -- identical in prior probe boots); the audit gates on node/material truth, pixels stay on-device.
> **Last updated 2026-10-27 (commons):** S15.7 THE UNDERWORLD'S WORLD-COMMONS SHIPPED -- lava is WATER-FRAME data (OceanVolume Liquid.WATER/LAVA + burn_dps; data/oceans/lava_underglow_lake.tres: LOCAL pool with a 0.35 m/s east-drift current and 8 dps; _build_lava_lake curb ring + molten disc, tide-pulsed; the visitor tick pays burns in whole digits through _burn_pool -- the debt books EVERY frame, the one-frame reset bug the probe caught) + FORMAL BIOME-BAND DATA (core/schemas/biome_band.gd + data/biomes/biome_underworld_*.tres x5; the wilds builders read count/radii/palette/clearances from the declarations, literals only when a declaration is missing; WILDS-OK byte-identical on the data path) + THE COMMONS: _build_trail (32 plates, camp->cistern->lake overlook), ThermalUpdraft gains world_id (data/thermals underworld_vent_east/vent_flow always-on + thermal_ascent_thrower RITUAL LAUNCHER feeding the East Stack -- the Ascent-door artifact beat, awakened via the ONE ThermalService ritual path), the underworld _process carries visitors through ThermalService.sample (lift + glide-tick + anticheat tickets), and weather_mist(phase) is the strata-mist fog law (0.055 -> 0.02 with the tide, fed per frame). COMMONS-OK (18 checks). Gates: underworld 44 / ocean 44 / CISTERN-OK / WILDS-OK / swim bridge 10/0 / naming lint 25/0 / lint 36/0 / packs 8 green.
> **Last updated 2026-10-27 (warden):** S15.6 THE WARDEN OWES THE CISTERN SHIPPED -- the swim BEAT + the dusk-read + the first wilds. Swim credit is a REAL bridge: OceanService emits `water_entered(body_id, volume_id)` once per dry->wet entry (`_wet_by` book; over-tick-proof), QuestService bridges it deferred into the new QuestData.ObjectiveType.SWIM, and quest_cross_the_cistern.tres targets `ocean_deep_root_pool` verbatim (previous_quest_id chain off quest_listen_to_the_deep; the Warden's greeting carries the cistern branch). The underworld is the LIVE delivery: _visitors hold body nodes and _process ticks every visitor through OceanService (world_root-local), probe_underworld G2 proves one frame in the dish closes the objective (44 checks now). Dusk-read PASS: cistern stone = one shared vein-lit wall mat whose energy rides the tide, darker slab, the bench as the brightest stone (static warm ember -- the exit reads); harbor lights pop at LAMP_ENERGY_LIT 1.8 + a warm halo OmniLight toggled by the same set_lit flip. DEEP WILDS: `_build_wilds` scatters FIVE bands (_wilds_drift golden-spindle, byte-identical on re-conjure): 12 crags / 7 dead trunks / 9 mycelium clumps / 14 stalagmites / 36 grass tufts; stones collidered, paint walks over; aprons keep gates + dish clear (`dev_temp/probes/wilds_probe.gd` WILDS-OK). Gates: underworld 44 / ocean 44 / swim bridge 10/0 / CISTERN-OK / LIGHT-OK / naming lint 25/0 / lint 36/0 / packs 8 green.
> **Last updated 2026-10-26 (cistern):** S15.5 THE GLOW CISTERN SHIPPED -- the Deep Root's catch-dish at the camp shelf: `data/oceans/ocean_deep_root_pool.tres` (LOCAL pool, floor on the walk line 2000.0, surface 2002.4, gentle) + `globe_underworld._build_cistern` (basin slab + 7 tall rim arcs 3.2 m + ONE sheave bench topping 0.3 m over the water = the one honest exit) + the cistern glow law riding the SAME Concord tide (`static cistern_glow(phase)` 0.45-1.0 cos band, high at the surface dawn). Receipt: `dev_temp/probes/cistern_probe.gd` CISTERN-OK; underworld 42 / ocean 44 / naming lint / lint 36/0 / packstruct --deep all green. Script-mode law: no parse-time preloads of game scripts (autoload names register after parse); the lint suite needs `GODOT=$(command -v godot)` after a workspace restore eats the /tmp binary.
> **Last updated 2026-10-26:** HARBOR LIGHTS + FLEET PACKS SHIPPED — S14.8's two-end light law (`entities/harbor_lights.gd`: PierBeacon caged lamp + MoorGuide ember panel, one flank step off the vessel law's dirs, `place_night` reads the Concord epoch the ferry tick already holds — lit dusk→dawn [18.0→6.0 sky hours], sea clamp `max(walk, sea)`; probe `dev_temp/probes/harbor_lights_probe.gd` LIGHT-OK with the berth held at 0.0000 rad). FLEET PACKS: `packs/public/` manifests are GENERATED from the runner's own DEFAULT_SET (`scripts/gen_fleet_packs.mjs`; 8 family packs = 101 tests, zero unfiled; `npx packstruct lint packs/ --deep` exit 0 — the missing-entry drift class the deck round hit dies at generation). The wake chain is complete: deck ride → wake credit → dock warp (warp landings pier-head/moor-bank; `FerryService.warp_wake` validate-only, world owns placement).
> **Last updated 2026-10-26 (deck):** S14.6 DECK RIDE SHIPPED — the Pans Runner's deck is now STANDABLE (piece-collider law in `ferry_vessel.build`: walkable DeckPanel + solid Hull/Hold + thin MastBlock; the old one-belt attach boxed the mast ~7 m up and left the deck unreachable) and `ferry_vessel.place()` carries who stands on her (rigid old→new carry; `deck_rides` anchor meta stamped/cleared by the ride roster; globe_player suppresses the terrain snap under the anchor — the deck panel is the ground, not the seabed law). Receipts: `dev_temp/probes/deck_ride_probe.gd` RIDE-OK (rigid carry 0.0005 m deck-local drift over a 1309 m park step; anchor clears on step-off) + the pans trio re-held + lint 36/0 + the ferry schedule contract. Next: wake-ledger credit for deck rides (the session dock still teleports at the ports, v0 contract). Earlier — **2026-10-19:** WEB/SITE SPLIT SHIPPED — `src/` is now a real site (lander `/`, `/play`, `/privacy`, `/terms`, gated `/admin`) on Vite + React 19 + react-router-dom 6 + Tailwind v4; prerendered by prestruct (`ssr.config.js` route list + `scripts/prerender.js` via `src/AppLayout.tsx` under StaticRouter; build = `npm run build`). Serving law: the raw engine client (`web/`) is served at **`/game/`** on the single domain (dev+preview middleware + `dist/game/` build copy + `public/_headers` for COOP/COEP + pack cache law); legacy `/web/` URL resolves as an alias only, never link it. Gates: `/play` and `/admin` share `src/lib/gate.ts` + `src/components/GateScreen.tsx` (sha256-of-password vs `VITE_GAME_PASSWORD_SHA` / `VITE_ADMIN_PASSWORD_SHA` build-time env, sessionStorage remember, 5s-doubling exponential attempt cooldown); real wall is the Cloudflare WAF rate rule documented in DEPLOY_WEB.md §5 — the gate is friction, not a boundary (static host law). The React 2D companion client, its modals, soundEngine, gameWebSocket mirror, and GodotClientView were REMOVED as tech debt (bridge service stays for admin). CI: `web-ci.yml` bakes `application/config/build_hash` into the pck (in-game truth line proves pack freshness) and uploads artifacts PR/dispatch-only with 3-day retention (push-era artifacts breached the 500 MB quota; `artifact-cleanup.yml` is the one-shot janitor); runner pinned `ubuntu-24.04`. Docs: `DEPLOY_WEB.md` (new web/site guide) + DEPLOY.md (now server-scope only). Guides live in these files; do not re-derive the split.
> **Last updated 2026-10-06:** S13 ROYALE storm shipped (`Contract.STORM_PHASES` + arena_instance `_storm_tick`; storm signals for the fog UI; glider drops; anticheat launch tickets + glide farm clamp). TRAVERSAL ARC: S14 ocean layer SHIPPED through S14.6 (water-as-data + OceanService, swim class + breath clock + pressure, aquatic anticheat + dive tickets + current drift, breather gear, ferries as closed-form schedule, water mounts as rated bodies; probes probe_ocean/probe_swim/probe_ferry/probe_water_mounts + co-located frame tests in the runner default set); S14.7 (the Sundered Sea content pass) remains. S15 underworld + S16 multiworld DESIGNED: `labs/prd-underworld.md` (planet-in-planet; dev/test env relocates there; OFFLINE to players), `labs/prd-multiworld.md` (WorldData registry, closed-form orbits, Moon Gate, world_moon). DEV-TARGET DECISION: the MOON hosts S16.6 dev/probes (the Builder's Pool is its test water); underworld stays the offline mystery layer. Agent memory: vant (axolotl) at workspace `/home/daytona/vant`, brain `cairn` (the agent is "Buffy, callsign Cairn" -- callsign `cairn` is used for ALL registry/brain/horcrux names because the vant engineer side already has a Buffy on the same master entity), org rig Synmergia > Frame Engineering > World Frame > world-frame-architect; disaster-recovery horcrux lives in `horcrux/` on main (password-in-filename convention, see `horcrux/README.md`). Earlier: 3D pipeline proven end-to-end (`scripts/gen_blacksmith_model.py` -> `game/models/npcs/`; exporter gotchas in `labs/prd-3d-pipeline.md` sec 6). Movement Design System: `data/movement_profiles/` + `MovementProfile` schema drive all speeds/gravity/capability gates. Hitbox Profile System: `data/hitbox_profiles/` + `HitboxProfile` schema drive all collision shapes; playable species share ONE player hitbox (species/sex never scale it). Skyward Concord: `labs/prd-psy.md` is worldview DESIGN LAW (no religion in Synmergia); SignService + `data/signs/` run the communal sky clock; AncientDoor re-seals at dawn and door_opened drives ActsService -- the Concord Chronicle (`data/acts/`, act_ prefix) records one chapter per solved day; SkyAlmanacUI (V key) has the Watch-the-sky far-gaze button; the Daily Class Blessing (sky wheel -> +20%/+5 levels for the named class, earn-gated on the code) is the retention beat; quest_watch_the_sky (RECORD_INSIGHT objective, resets at the sky dawn) is the daily beat; the blessed class wears the sky-cyan mote ring + "(*)" sigil (entities/blessed_mark.gd -- NO class_name, preload it; statics late-resolve autoloads) in titles/chat, never GM gold; ChronicleUI (J key) is the lore shelf; chapter-gated mysteries (`data/mysteries/`, `mystery_` prefix, answers DERIVED never stored) solve for titles + XP through ActsService; AudioService (`game/audio/`, WAVs generated by `scripts/gen_door_open_audio.py`) is the repo's only sound path, and a door open erupts the amber PayoffPillar + shard-wide chime. Regression set: `sh ./scripts/godot_test_runner.sh`.
> Accessibility + Agent-Action layer (labs/prd-accessibility.md, SHIPPED rounds 1-5): UIStyles.apply_accessibility writes the real AccessKit properties, A11yService (autoload) runs the [A11Y] stream (menus + world/entity:<id> entries) and focus_next/prev, engine AT support is Auto in project.godot, palette contrast is enforced by tests/test_a11y_contrast.gd (runner default set), and the web probes live in scripts/web_probe/ (window.__synA11yDump() is the agent dump hook; never a human hotkey).
> The hard gate (2026-10-06): `WardGateService` + `data/gates/` (`gate_`
> prefix, filename == id) hold the admin keys (reserved role 0 + the
> Skywarden token, fail-closed on every leg) and the breach embargo
> (embargoed drops die at creation AND pickup; `labs/prd-ward-gate.md`);
> `probe_ward_gate` in the runner default set.

## READ FIRST

Three things that have caused repeated agent damage in this
repo. If you only read one section of this file, read these:

1. **[Autoloads and class_name](#autoloads-and-class_name)** —
   the autoload identifier and `class_name` register different
   things. Putting them on the same script with the same name
   silently breaks code. Read this BEFORE adding any new
   autoload or class.
2. **[Tabs, not spaces](#indentation)** — once a `.gd` file uses
   tabs, every subsequent line must use tabs. Mixed indentation
   is a parse error in 4.7.2.
3. **[No UTF-8 in source](#code-standards)** — emoji, smart
   quotes, and non-ASCII characters cause Godot import failures.
   The existing codebase has 142 lines with emoji (mostly in
   `discord_webhook.gd` and `waypoint_service.gd`); don't
   add more.

---

## Project Overview

Synmergia is a Godot 4.7.2 based MMORPG with an authoritative
server architecture. The architecture has four layers:
**Godot client → Multi-iso orchestrator → State tree
(content-hash) → Postgres + cache**. The orchestrator and
state tree are the **frame**; they live in `/game/core/frame/` and can
extract to their own project.

- **Language:** GDScript
- **Engine:** Godot 4.7.2
- **Architecture:** Client + Authoritative Server + Multi-iso orchestrator + State tree
- **Game root:** `game/` (open this in the Godot editor)
- **Frame root:** `/game/core/frame/` (in Godot project)
- **Persistence layer:** `game/adapters/` (Postgres, Redis, memory)
  — defined in `labs/prd-db.md`. Adapter layer is the official
  interface for all service-level storage.

---

## Code Style Conventions

### Indentation
- **GDScript files (.gd)**: Use **tabs** (not spaces)
- Tab width: 4 characters visually
- `.editorconfig` is configured for automatic enforcement

### Naming Conventions
- Files: `snake_case.gd`
- Classes: `PascalCase`
- Signals: `entity_spawned`, `player_joined`, `target_acquired`
- Enums: `PascalCase.VALUE` (e.g., `Entity.EntityType.PLAYER`)
- Constants: `SCREAMING_SNAKE_CASE`

### Code Patterns
- **Inner classes** for related utilities:
  - `SpawnMetadata`
  - `NotificationService.AlertScope`
  - `NotifKind`
  - `CommunityGovernance.Vote`
  - `CommunityGovernance.ModeratorProgression`
- **Signal naming:** verb past tense (`entity_spawned`, `player_left`)
- **Factory methods** for complex object creation
- **Service singletons** via autoload
- **Frame primitives** in `/game/core/frame/`: NO autoload, NO `class_name`, NO GameManager dependency

### Working with Code

**File Editing:**
- Shell commands and heredocs can be problematic to edit programmatically — prefer direct file edits when possible
- Pay close attention to indentation (GDScript uses tabs, not spaces)
- Always check for unclosed braces, parentheses, and quotes

**Code Standards:**
- Use **tabs** for indentation in GDScript files — `.editorconfig` enforces this
- **No UTF-8 special characters** in the codebase — they cause Godot import issues
- Use `TODO` comments for incomplete work or stubs
- Avoid legacy code, wrappers, and aliases — use current methods when available

**Implementation:**
- Wire and integrate features as you go — look for other code that could benefit from the same wiring
- **Work to completion** — avoid leaving code in a half-baked or non-functional state
- Use existing architecture, methodology, and systems — don't reinvent patterns or go rogue
- The system should function as a **cohesive unit**, not a scattered collection of unrelated pieces

---

---

## Autoloads and class_name

Autoloads are singleton services available globally. `class_name` registers a
script's type as a global identifier. **They look identical when you write
code but behave very differently.** Misuse causes silent runtime errors
(null instance, wrong method dispatch) that cascade through `_ready` and
look like parse errors elsewhere.

**The two rules:**

1. **Autoload name and `class_name` MUST NOT be the same string.** The
   autoload identifier shadows the class_name; you lose the ability to
   call `X.new()` or `extends X` reliably. One of them wins, the parser
   does not warn, and the loser silently does the wrong thing.

2. **Autoloads cannot be instantiated.** `X.new()` on an autoload
   identifier fails at runtime (autoloads are Nodes, not Scripts).
   To make a fresh instance, `load("res://path.gd").new()`.

### Naming

| Aspect | Rule | Example |
|--------|------|---------|
| Filename | `snake_case.gd` | `notification_service.gd` |
| Autoload name | `PascalCase` | `NotificationService` |
| `class_name` | Pick one of: omit it OR rename it differently from the autoload | `class_name NotifDispatcher` is OK; `class_name NotificationService` is NOT if `NotificationService` is also an autoload |

### When to add `class_name`

Add `class_name` when you need to:

- **Instantiate**: `var x := MyClass.new()` (the class is not an autoload)
- **Type-annotate a parameter or variable**: `func process(e: MyClass)`
- **Type-check at runtime**: `if node is MyClass`

Do **not** add `class_name` when the script is an autoload, unless you have
a concrete reason (see below). Autoloads are already globally accessible by
their autoload name; adding `class_name X` where X is also the autoload name
creates a shadow.

### The one case where `class_name` on an autoload is legitimate

If a file is an autoload AND is also extended by other classes (e.g.
`extends Entity` where `Entity` is an autoload), then `class_name Entity`
on the base script is needed so the parser can resolve the parent type
in the `extends` statement. But this is a **smell**: the script is doing
two things (base class + autoload singleton). If you find yourself here,
consider:

- **Option A**: Split. Make the base class its own file (no autoload),
  have the autoload be a small wrapper that `extends BaseClass` and adds
  the singleton state. Other code does `extends BaseClass` and
  `BaseClass.new()`. No shadow.
- **Option B**: Keep `class_name`, but use the autoload ONLY for the
  singleton globals (logger, registry, dispatcher) and never call
  `Entity.new()`. To spawn new entities, use a dedicated subclass
  (`class_name EnemyEntity extends Entity` in a separate file) or
  `load("res://core/entities/entity.gd").new()`.

The current code uses **Option A** for `Entity`: the base class
`res://core/entities/entity.gd` is **not** an autoload. The autoload
was removed from `project.godot` and the script now exposes only
`class_name Entity`. Spawning is done via `Entity.new()` (or
`load("res://core/entities/entity.gd").new()` from contexts that
should not depend on the global class registry). Subclasses
(`extends Entity`) live in `entities/enemy.gd`,
`core/entities/npc_entity.gd`, and `core/entities/skill_academy_npc.gd`.

The old `const Entity = preload("res://core/entities/entity.gd")`
workarounds in 27 callers were removed: they are no longer needed
since `class_name Entity` resolves cleanly without an autoload shadow.
The regression test `tests/test_entity_autoload.gd` covers the fix.

**Allowlist of intentional `class_name` + autoload collisions.** A
small number of autoloads keep both, and they are tracked in
`tests/test_autoload_audit.gd`:

- `QoSService` -- the script exposes static shim methods (e.g.
  `QoSService.rate_limit(...)`) that internally resolve the autoload
  at runtime. The static methods are convenience wrappers; the
  actual state lives in the autoload. The class_name also lets
  callers type-annotate `func (svc: QoSService)`. Do not add more
  entries to this allowlist without updating the audit test and
  this section.

### Accessing autoloads

```gdscript
# Correct: use the autoload name directly (it's already an instance)
NotificationService.notify(...)
QoSService.rate_limit(player_id, "combat")

# Correct: type-check via the autoload name (no class_name needed)
if node.get_parent() == GameManager:
    pass

# Correct: type-annotate a parameter using the autoload name
func process(svc: NotificationService) -> void:
    pass

# Wrong: trying to create a new instance of an autoload
var ns := NotificationService.new()  # FAILS at runtime

# Correct: instantiate a non-autoload class
var math := CombatMath.new()         # class_name CombatMath, no autoload
```

### Extending an autoload's script

```gdscript
# If the autoload file has class_name, this works:
extends Entity  # requires class_name Entity in entity.gd
class_name EnemyEntity

# If the autoload file does NOT have class_name, you must preload:
const EntityScript = preload("res://core/entities/entity.gd")
extends EntityScript
class_name EnemyEntity
```

Preload is more verbose but removes the shadowing risk. Prefer it when
the base script is an autoload.

### Autoload order

The autoload list in `project.godot` is the load and `_ready` order. Top
to bottom. If autoload A's `_ready` calls a method on autoload B, then
A must be listed **after** B. Get this wrong and you get:

```
Attempt to call function 'X' on a null instance
```

This error is misleading. It points to the *caller* (A) but the *cause*
is the *callee* (B) not being ready. Walking the call stack backward
often reveals the real problem.

To check autoload order:

```bash
awk '/^\[autoload\]/{flag=1; next} /^\[/{flag=0} flag' game/project.godot \
  | grep -oP '^\w+(?==)'
```

To detect forward references (autoload using another that comes later
in the list), scan each autoload's source for bare references to other
autoload names. A reference like `GameManager.foo` in `QoSService.gd`
is a forward reference if `GameManager` is listed after `QoSService`
in the autoload list.

### Cycles

Three flavors of cycle, all silent:

1. **`_ready` cycle**: A._ready() calls B.method(), B._ready() calls
   A.method(). Both fail with null instance. No "circular dependency"
   diagnostic. Fix: defer the cross-service calls with
   `call_deferred()` or `await get_tree().process_frame`.

2. **Preload cycle**: A preloads B, B preloads A. Parse error in both
   files. The error message names both, but the root cause is the
   cycle, not the parse error. Fix: extract a third file C that both A
   and B depend on, or use `load()` (runtime) instead of `preload()`
   (parse-time) for one of the references.

3. **Autoload name cycle**: A's autoload entry references B (via direct
   call in `_ready`), B's references A. Same null instance error as
   case 1. Fix: same as case 1.

### When you cannot `extends` an autoload

You cannot use an autoload as the parent class in `extends`. The autoload
is a singleton instance, not a script type. If you need to extend the
script that backs an autoload, you must give that script a `class_name`
(no name collision with the autoload) or preload it.

### Self-recovery playbook (when in a loop)

If the project won't load and you're seeing a cascade of errors:

1. **Stop and identify the FIRST parse error.** Godot reports many
   files failed; usually one is the root cause and the rest are
   downstream. Read the error list top to bottom.

2. **For each candidate root file, check**:
   - Does the file have `class_name X` where X is also an autoload?
     Remove the `class_name` or rename the autoload.
   - Is the file trying `X.new()` where X is an autoload? Use
     `load("res://path.gd").new()` or refactor to a subclass.
   - Does the file extend an autoload's script? Add `class_name` to
     the parent (no collision) or use `preload(...).new()`.
   - Does the file reference an autoload that comes LATER in
     `project.godot`? Move the reference to `call_deferred` or move
     the autoload up in the list.
   - Is the file using a reserved keyword as a variable name
     (`class_name`, `signal`, `func`)? Rename it.
   - Mixed indentation (tabs vs spaces)? Run `cat -A file.gd` to see
     the actual whitespace; pick one and stick to it.
   - `Resource.get("key", default)` parse error? In 4.7.2, default
     args to `Resource.get` were removed. Use `if resource.has(key)`
     guard or `resource.get(key, null)`.
   - Type inference on ternary (`var x := a if cond else b`)? Add
     explicit type: `var x: T = a if cond else b`.

3. **If the file itself is unrecoverable**, do NOT delete the
   business logic as a first resort. Instead:
   - `git stash` to save the working file
   - Reduce the file to: `## Header\nextends Node\nconst Deps = preload(...)`
   - Verify the rest of the project loads
   - Restore the file piece by piece (or use `git checkout HEAD~1 -- file`)
     to find which lines reintroduce the error

4. **Last resort: gut the file.** Only acceptable if (a) the file is
   not on the critical path for the boot sequence, (b) you've checked
   that no other file preloads it, and (c) you record the deletion
   in the commit message with `BREAKING:` so a future agent can
   restore it from history. The pattern:
   ```
   ## OldName - what it did
   ## One-line summary of what was lost
   extends Node
   const Dep = preload("res://path.gd")
   ```
   This is a 3-line stub that does not cascade.

5. **If a stub was created, file a follow-up** to restore the
   implementation. The git history (`git log --all -- path/to/file.gd`)
   has every prior version.

### Diagnostic commands

```bash
# List autoloads in order
awk '/^\[autoload\]/{flag=1; next} /^\[/{flag=0} flag' game/project.godot \
  | grep -oP '^\w+(?==)'

# Find class_name collisions with autoloads
awk '/^\[autoload\]/{flag=1; next} /^\[/{flag=0} flag' game/project.godot \
  | grep -oP '^\w+(?==)' | sort -u \
  | while read a; do
      grep -lP "^\s*class_name\s+${a}\s*$" game/ -r --include="*.gd"
    done

# Find .new() calls on autoload names
# (autoloads are PascalCase; bare class_names are also PascalCase; this
#  returns all .new() calls; manually filter for autoloads)
grep -rEn "\b[A-Z]\w+\.new\(\)" game/ --include="*.gd"

# Find tabs vs spaces in a file
cat -A game/path/to/file.gd | head -5  # ^I = tab, $ = end of line
```

## Architecture

### Core Services (Autoloaded)

A curated subset. For the full autoload list (50+ entries), see
`game/project.godot` `[autoload]` section. This table groups by
purpose; if a service is missing here, it doesn't mean it doesn't
exist.

| Service | Purpose |
|---------|---------|
| **Core base class** | |
| `Entity` | Base class for all entities (`class_name Entity`, NOT an autoload). Use `extends Entity` and `Entity.new()`. |
| **World building & frame** | |
| `FrameService` | Frame execution isolation, seed authority, and T3 state tree management (D030). |
| `ShardParameters` | Dynamic world/shard parameters with immediate or 5-min coalesced persistence (D033). |
| `OpenSeedRegistry` | Reconnect window TTL tracking (5-min default) and instance state finalization (D032). |
| **Storage / persistence** | |
| `AdapterRegistry` | Pluggable storage adapter registry. See `labs/prd-db.md` for the spec. |
| `BackendFactory` | Builds persistence + cache adapters from config. Used during boot. |
| **Event & notification** | |
| `EventHub` | Central event hub with unified entity signals (was named `EventBus` historically). |
| `NotificationService` | Player notifications and alerts. Use `notify()` not `send_to_player()`. |
| **Game state** | |
| `GameManager` | Overall game state, player management |
| `GameLog` | Centralized logger. Use `GameLog.info()` / `GameLog.warn()` / `GameLog.error()`. |
| `GameConfig` | Game-wide configuration access |
| `PlayerConfig` | Per-player config (loaded from disk) |
| **Entities & spawning** | |
| `EntityService` | Track all entities (players, enemies, NPCs) |
| `SpawnService` | Enemy/NPC spawning with metadata |
| `ZoneManager` | Zone transitions and state |
| **Networking** | |
| `NetworkManager` | Authoritative server transport, peer management |
| `PlayerManager` | Connected player state, peer ↔ player_id mapping |
| `InputManager` | Client-side input handling |
| `InteractionLayer` | Range-based interaction resolver |
| **Combat & targeting** | |
| `TargetingManager` | Unified targeting system |
| `CombatSystem` | Combat loop, ability resolution |
| `CombatMath` | Damage/effect calculations (NOT an autoload; a static utility class) |
| `AuraComponent` | (component) Buffs/debuffs |
| `AggroComponent` | (component) Threat/aggro management |
| **Player systems** | |
| `InventoryService` | Player inventory management |
| `TradeService` | Item trading |
| `PartyService` | Party/raid management |
| `GuildService` | Guild management |
| `LootService` | Loot distribution |
| `RespawnService` | Player respawn logic |
| `DeathFeatures` | Death screen, corpse, recovery options |
| `FactionManager` | Faction relationships and PvP modes |
| **Account & login** | |
| `AccountService` | Account creation, password reset |
| `LoginService` | Login + character selection |
| `FriendsService` | Friends list, requests, block/ignore |
| `SameAccountTransferService` | Cross-character transfer within one account |
| **World content** | |
| `DataService` | Static data loader (`.tres` files) |
| `WorldService` | World state, instances, save/load |
| `ShardManager` | Multi-shard routing |
| `ServerManager` | Per-server lifecycle |
| `DialogService` | NPC dialog trees |
| `QuestService` | Quest state and progress |
| `ActsService` | Concord Chronicle (acts/chapters on door_opened) + mystery ledger |
| `AudioService` | Round-robin WAV playback (play/play_world/play_ui); generated assets in `game/audio/` |
| `AchievementService` | Achievement tracking and unlocks |
| `TitleService` | Player titles, prefix/suffix display |
| `WaypointService` | Waypoint discovery, fast travel |
| `FollowService` | Player /party follow mode |
| `BlacksmithService` | Item crafting/upgrading |
| `SkillAcademyService` | Skill learning, training |
| `StarterKitService` | New character starting equipment |
| `VaultService` | Account-wide shared storage |
| `RespawnUIManager` | UI for respawn flow |
| **Moderation & safety** | |
| `AutoResponseService` | Admin alerts and moderation |
| `SecurityService` | Anti-cheat and rate limiting |
| `AppFirewall` | Tool-call firewall, depth limits, recursion guards |
| `SecurityMonitor` | Security event aggregation |
| `CommunityGovernance` | Voting, moderator progression |
| `PermissionManager` | RBAC for admin commands |
| `PlayerReporter` | Player report handling |
| `AdminCommands` | Admin command dispatcher |
| **Infrastructure** | |
| `QoSService` | Latency and rate limiting (also has `class_name`; no `.new()`) |
| `IDRegistry` | Stable ID generation for content |
| `PlayerLockService` | Per-player mutex to prevent race conditions |
| `CooldownService` | Cooldown tracking |
| `SlotService` | Data-driven item slots, no legacy fallbacks |
| **System** | |
| `RegisterTypes` | Type registry initialization (autoload before all services) |
| `DebugOverlay` | Debug HUD (autoload; F-key toggled) |
| `ScreenshotService` | Screenshot capture and storage |
| `WebhookManager` | Outbound webhook dispatch |
| `AntiCheatService` | Server-side anti-cheat detection |

> **Naming caveat:** `EventBus` may appear in comments or older
> code, but the autoload is `EventHub`. If you see `EventBus.X`,
> check whether it's a pre-rename reference (replace with
> `EventHub.X`) or the `class_name SpawnMetadata` (which is a
> bare global defined in `game/core/events/spawn_metadata.gd`).

### Components (Attached to Entities)

| Component | Purpose |
|-----------|---------|
| `HealthComponent` | Health, death, respawn |
| `CombatComponent` | Combat state, skills, damage |
| `AuraComponent` | Buffs/debuffs |
| `AggroComponent` | Threat/aggro management |
| `InventoryComponent` | Item storage and equipment |

### UI Components

| Component | Purpose |
|-----------|---------|
| `UIStyles` | Common styling, colors, fonts |
| `UIPanel` | Base panel class with overlay |
| `ActionMenu` | Context menus (mouse/touch) |
| `TooltipManager` | Unified tooltip system |
| `MenuManager` | HUD management |
| `InventoryUI` | Player inventory grid |
| `BuffBar` | Buff/debuff display |
| `GuildUI` | Guild management |
| `PartyUI` | Party management |
| `TradeUI` | Item trading interface |

---

## Event Patterns

**Unified entity events carry `SpawnMetadata`:**
```gdscript
# Signal signature:
entity_spawned.emit(entity: Entity, metadata: SpawnMetadata)

# Handler must match:
func _on_entity_spawned(entity: Entity, metadata: SpawnMetadata) -> void:
    pass
```

> **WARNING:** Mismatched signal handlers cause runtime errors. Always verify signatures.

---

## Common Operations

### Creating Spawn Metadata
```gdscript
var metadata := SpawnMetadata.world_boss("Dragon", "zone_1", position, 50)
```

### Accessing Enums
```gdscript
# SpawnMetadata types
var type := SpawnMetadata.SpawnType.BOSS
var priority := SpawnMetadata.NotificationPriority.CRITICAL

# Entity types
if target.entity_type == Entity.EntityType.PLAYER:
    pass

# Notification types
NotifKind.WARNING
NotifKind.ALERT
```

### Sending Notifications

Use the **typed-Kind pipeline** (`NotificationService.notify()`) for
all service-level toasts. The frame handles dedupe, type-mapping, and
priority automatically based on the kind.

```gdscript
const NotifKind = preload("res://core/notifications/notification_kind.gd").NotifKind

# To a specific player
NotificationService.notify(
    NotifKind.ITEM_ADDED,
    "Picked up Sword of Truth",
    "InventoryService",                       # source_service label
    "inv_add:%s:%s" % [player_id, item_id], # dedupe key (5s window)
    {"item_id": item_id, "rarity": "epic"},
    player_id                                 # recipient
)

# Server-wide / admin scope (recipient = "")
NotificationService.notify(
    NotifKind.ADMIN_ALERT,
    "RecursionGuard exceeded depth 16",
    "AppFirewall",
    "fw:%s" % message.hash(),
    {"context": "agent_tool_call", "depth": 16}
)
```

> **Don't** call `NotificationService.send_to_player()` directly for
> new code — that's the legacy path. Use `notify()` instead.

### Notification → Toast Pipeline
Every service-level event ends up in a toast panel in `HudLayer`:

```
Service → NotificationService.notify() → NotificationDispatcher → TooltipManager.show_toast()
```

When adding a new service:
- For **in-game state changes** (death, level-up, item equipped): emit a typed signal
- For **infrastructure events** (throttled, restricted, banned): call `notify()` so the player sees a toast

```gdscript
# GOOD (infrastructure): player must see the toast
NotificationService.notify(NotifKind.RATE_LIMITED, "You're casting too fast", "QoSService", ...)

# GOOD (in-game state): emit a signal
signal item_equipped(player_id: String, item_id: String)
item_equipped.emit(player_id, item_id)
```

### Range-Based Entity Queries
```gdscript
var nearby := EntityService.get_entities_in_radius(
    player.global_position,
    20.0,  # range
    Entity.EntityType.PLAYER
)
```

---

## File Organization

```
.
├── game/                          # the Godot 4.7.2 project
│   ├── adapters/                  # Storage adapter layer (Postgres, Redis, memory)
│   │   ├── persistence/           # PersistenceStore interface + impls
│   │   ├── cache/                 # CacheStore interface + impls
│   │   ├── memory_layer/          # In-memory state store
│   │   ├── registry.gd            # AdapterRegistry autoload
│   │   ├── backend_factory.gd     # BackendFactory autoload
│   │   └── README.md              # Adapter layer spec summary
│   ├── core/
│   │   ├── admin/                 # Admin shell, permission, reports
│   │   ├── ai/                    # NPC AI (decision trees, behaviors)
│   │   ├── autoload/              # Global singletons (~20)
│   │   ├── combat/                # Combat system, ability resolution
│   │   ├── community/             # Voting, moderator progression
│   │   ├── components/            # Entity components (health, combat, etc.)
│   │   ├── entities/              # Base entity classes (Entity, NPCEntity, ...)
│   │   ├── events/                # Event hubs + metadata types
│   │   ├── frame/                 # Frame primitives (moved from labs/)
│   │   │   ├── math/              # NSC-9, icosahedral
│   │   │   ├── kv/                # LRU, state_tree, T3
│   │   │   ├── srv/               # RulesEngine, ScopeEngine, Markov, LOD, Axis
│   │   │   └── db/                # snapshot_store
│   │   ├── input/                 # Interaction layer, input maps
│   │   ├── notifications/         # NotificationService + NotifKind enum
│   │   ├── schemas/               # Data schemas (Resource subclasses)
│   │   ├── services/              # Game services (30+)
│   │   ├── targeting/             # Targeting system
│   │   ├── ui/                    # Core UI base classes
│   │   └── utils/                 # Generic utilities (id_registry, app_firewall, ...)
│   ├── entities/                  # Concrete entity types (enemy, character, ...)
│   ├── scenes/                    # .tscn scenes (world, NPCs)
│   ├── connectors/                # AI agent connectors (discord, webhook, ...)
│   ├── data/                      # .tres resources (static data)
│   ├── ui/                        # User interface (panels, dialogs, HUD)
│   └── tests/
│       ├── adapters/              # Adapter layer tests (unit + integration)
│       └── *.gd                   # Smoke tests (one per major system)
│
├── labs/                          # Frame + design docs
│   ├── prd.md                     # Product requirements
│   ├── prd-db.md                  # Storage adapter spec (authoritative)
│   ├── TASKS.md                   # Session log + open tasks
│   ├── world-building*.md         # World/architecture docs
│
├── srv/                           # Deployment configs (docker, certs)
├── AGENTS.md                      # This file
└── README.md                      # Project overview
```

The Godot project root is `game/`. The `labs/` directory is outside
the project so it doesn't taint the stable build with experimental work.

`game/adapters/` is the **only** directory that services should use
for persistence. See `labs/prd-db.md` for the full spec.

---

## Scene & World Naming Conventions (spatial layer)

Decided 2026-09-30 after the globe rename. The DATA layer names by
category prefix (`world_`, `zone_`); the SCENE layer names by
containment relation so orbit/nesting is readable from the filename.

| Thing | Pattern | Example |
|-------|---------|---------|
| Generic globe scene (radius from `synmergia/world/planet_radius` -- boots AS Synmergia at 20 km, the prototype at 100 m) | `globe_world.gd/.tscn` | the S3 spherical scene root |
| A world's moon globe | `globe_<world>.gd/.tscn` | `globe_moon.gd` (the pale stone, dev target) |
| Future orbiting/nested bodies | `globe_<world>` | `globe_underworld` when S15 gets its own scene (today it reuses the generic globe via `world_underworld.tres` radius) |
| Runtime node names | `Globe<Scope>`, PascalCase | `GlobeWorld`, `GlobeMoon` (globe_driver waits on these names) |
| Player controller on any globe | `globe_player.gd` (`class_name GlobeWorldPlayer`) | scope-generic on purpose; one controller, every globe |
| World declarations (data) | `world_<id>.tres` | `world_main.tres` (Synmergia), `world_moon.tres` (the pale stone), `world_underworld.tres` (The Deep Root) |

Rules:
- Scene filenames never contain category words in REVERSE order
  (`moon_globe` was the inconsistency; fixed to `globe_moon`).
- The generic globe scene is NOT named after any one world -- it is
  the shape, and `world_<id>.tres` declarations give it identity
  (radius, gravity, orbit, lore). One scene, every planet.
- Canon display names live ONLY in the .tres (`display_name`,
  `lore`); code comments may use them, code identifiers may not.
  Canon today: planet = Synmergia, moon = the pale stone,
  underworld = The Deep Root.
- When renaming a scene, grep `globe_driver.gd` node-name waits and
  the `game/tests/probe_*` paths BEFORE committing; the runtime node
  name changes with the file (`.tscn` root `name=`).

## ID Naming Conventions (data ids)

Decided 2026-09-25 after the data/npc + data/npcs consolidation.
One id per entity, filename equals the id for prefixed categories,
and NO dual-format compatibility shims in code (no trim_prefix
fallbacks, no display-name OR id candidate loops). Quest bridges and
consumers read exactly one form.

| Category | Id style | Example | File |
|----------|----------|---------|------|
| NPCs | `npc_` prefix | `npc_village_elder` | `npc_village_elder.tres` |
| Quests | `quest_` prefix | `quest_wolves_hunt` | `quest_wolves_hunt.tres` |
| Zones | `zone_` prefix | `zone_starter_plains` | `zone_starter_plains.tres` |
| Factions | `faction_` prefix | `faction_human` | `faction_human.tres` |
| Items | kind prefix | `wep_iron_sword`, `potion_soul_gem`, `res_iron_ore` | filename == id |
| Misc items (data/items) | `item_` prefix | `item_ancient_coin` | filename == id |
| Quest items | `item_quest_` prefix | `item_quest_sealed_writ` | filename == id, `is_quest_item = true` |
| Status effects | `buff_` prefix | `buff_barrier_field` | filename == id |
| Loot tables | `loot_` prefix | `loot_wolf` | filename == id |
| Hitbox profiles | `hitbox_` prefix | `hitbox_beast_medium` | filename == id |
| Sky Signs | `sign_` prefix | `sign_the_awakening` | filename == id |
| Chronicle Acts | `act_` prefix | `act_1_the_first_vault` | filename == id; chapters are plain dicts (the QuestData pattern); no faith language in copy (prd-psy sec 4) |
| Mysteries | `mystery_` prefix | `mystery_the_first_vault` | filename == id; answers are DERIVED (never stored) -- SKY_CODE re-derives SignService.get_ancient_code(answer_day), OBSERVATION_TALLY from the live sign catalog; reward titles must exist in data/titles |
| Daily sky quest | `quest_watch_the_sky` | `quest_watch_the_sky.tres` | RECORD_INSIGHT objective targets the literal `sky_insight`; reset keys off SignService.current_day_index() |
| Ancient doors | bare id on the node | `AncientDoor` (entities/ancient_door.gd) | no .tres (door state is SignService unlock history) |
| Dwellings | `dwel_` prefix | `dwel_fireplace_stone` | filename == id |
| Currencies | `currency_` prefix | `currency_gold` | filename == id |
| Mounts | `mount_` prefix | `mount_plains_runner` | filename == id |
| Vehicles | `veh_` prefix | `veh_haven_ferry` | filename == id |
| Accessories (items) | `acc_` prefix | `acc_ring_first_light` | filename == id |
| Enemies | bare id | `wolf` | `enemy_wolf.tres` (file keeps prefix) |
| Dialogues | bare id | `village_elder_greeting` | filename == id |
| Offerings | bare filename key | `village_quests` | `village_quests.tres` |
| Species / titles / achievements / world bosses / targets | bare id | `human`, `slayer`, `first_blood` | filename == id or schema prefix |

Quest data contracts (single-form, no fallbacks):
- TALK objectives target the NPCData id verbatim (`npc_village_elder`).
- EXPLORE objectives target the ZoneData id verbatim (`zone_starter_plains`).
- KILL objectives target the enemy display_name ("Wolf") -- combat
  bridge credits display_name.
- COLLECT objectives target the item display_name ("Moonpetal Flower").
- Quest items (Item.is_quest_item) carry a resolvable `quest_id` and
  never vendor; the lint enforces the ref.

`game/tests/test_data_naming_lint.gd` enforces the prefixed styles,
filename==id, and cross-file references (zone_id, quest chains,
giver/turn_in, offering quest_ids, dialogue npc_id, zone rosters).
Run it after adding or renaming any data ids.

## Data Schemas

### TargetSchema (`data/targets/`)
- `target_player.tres`, `target_enemy.tres`, `target_npc.tres`
- `target_loot.tres`, `target_dwelling.tres`, `target_gateway.tres`

### EnemyData
- `enemy_type`: NORMAL, ELITE, BOSS, WORLD_BOSS
- `level`, `health`, `attack_power`, `defense`

### Item
- `soulbound`, `bind_on_pickup`, `bind_on_equip`
- `unique`, `stack_size`, `rarity`

### GM Classes
Three admin-only classes hidden from normal character selection:
- `gm_akkan`, `gm_human`, `gm_synthetic`
- All have `role = 0` (Role.GM)

GM visibility: `[GM]` prefix in chat, gold name color, "GAME MASTER" badge in tooltip (no emoji; see the no-UTF-8 rule).

---

## Labs Conventions

The `/labs/` directory is for experimental primitives that could
extract to the multi-iso frame. Different rules apply:

| Rule | Game (`game/`) | Frame (`labs/`) |
|------|-----------------|-----------------|
| Autoload | Yes (mind the rules) | No |
| `class_name` | Only when needed (see below) | No |
| GameManager dep | Allowed (singleton access) | No |
| Adapter layer | Yes (Postgres, Redis, memory) | No (pure functions) |
| Tests | Co-located in `game/tests/adapters/`, smoke tests in `game/tests/` | Co-located (`foo.gd` + `test_foo.gd`) |

> **`class_name` in `game/`:** add it ONLY when you need
> `X.new()`, type-annotation, or `is X` checks. Do not add it
> to autoloads (the autoload name is already a global
> identifier). Do not add it to scripts that are only ever
> used by `preload`. See [Autoloads and class_name](#autoloads-and-class_name)
> for the full rules.

### Frame Primitive Rules
1. Each primitive is its own `.gd` file
2. Tests are co-located: `nsc9.gd` + `test_nsc9.gd`
3. No autoload, no `class_name`, no GameManager dependency
4. New code goes here first. The game consumes from here.

### Frame Contents
| Subdirectory | Contains | Examples |
|--------------|----------|----------|
| `game/core/frame/math/` | Pure functions. No state. | NSC-9 encoding, icosahedral projection |
| `game/core/frame/geometry/` | Pure functions for spatial addressing | NSC-9 encoding, spatial fragmenter, bridge |
| `game/core/frame/kv/` | In-memory data structures | LRU cache, content-hash, state tree |
| `game/core/frame/srv/` | Service logic | RulesEngine, ScopeEngine, Markov, LOD, Axis |
| `game/core/frame/db/` | Database integration | snapshot_store, migrations |

See [`labs/README.md`](./labs/README.md) for the full conventions.

---

## Security: BBCode XSS

All `RichTextLabel` nodes have `bbcode_enabled = true`. User-supplied
strings embedded in BBCode format strings are a potential injection vector.

**Pattern to avoid:**
```gdscript
"[color=%s]%s[/color]" % [color, user_string]   # DANGEROUS
```

**The fix:** Replace `[` and `]` with full-width equivalents:
```gdscript
static func _esc(text: String) -> String:
    return text.replace("[", "［").replace("]", "］")
```

**Files with this pattern:**
- `core/services/chat_service.gd`
- `ui/components/combat_log.gd`
- `ui/components/chat_ui.gd`
- `ui/components/dialog_ui.gd`
- `ui/admin/admin_dashboard.gd`
- `core/admin/player_shell.gd`
- `core/autoload/logger.gd`
- `core/services/qos_service.gd`
- `core/services/security_service.gd`

When adding new `RichTextLabel` BBCode with user input, always pass it through `_esc()` first.

---

## Important Patterns

### Null Checks for Services
Always check if a service exists before using:
```gdscript
if NotificationService:
    NotificationService.send_to_player(player_id, message)
```

### Instance Validation
Always validate entities before use:
```gdscript
if is_instance_valid(entity) and entity.entity_id != sender_id:
    # safe to use
```

### Defensive Helper Pattern
When a helper bridges two services, prefer try-known-methods fallback:
```gdscript
func _get_peer_for_player(player_id: String) -> int:
    if PlayerManager == null:
        return -1
    for method_name in ["get_player_info", "get_player", "find_player"]:
        if PlayerManager.has_method(method_name):
            var result = PlayerManager.call(method_name, player_id)
            if result is Dictionary:
                var info: Dictionary = result
                var peer_id = info.get("peer_id", -1)
                if peer_id is int and peer_id > 0:
                    return peer_id
    return -1
```

### Godot GDScript Rules
- **`extends` must precede `class_name`** when both are present
- **Mixed indentation is fatal:** Once a file uses tabs, every subsequent line must use tabs
- **Inner class methods cannot call outer class methods** without qualification
- **`extends Control` for scene-instantiated UIs:** Use `extends Control` + manual stubs for UIPanel methods

### NPC Scene Pattern
NPC entities use `scene_path` in NPCData to specify their `.tscn`:
```gdscript
# NPCData schema
@export var scene_path: String = ""  # Path to NPC .tscn scene

# SpawnService loads the scene and configures it:
if npc_data.scene_path:
    var packed := load(npc_data.scene_path) as PackedScene
    var entity := packed.instantiate() as NPCEntity
```

### Player Spawn Signal
Use `GameManager.player_entered_world` to trigger services when a player enters:
```gdscript
# Connect in your service:
GameManager.player_entered_world.connect(_on_player_entered)

func _on_player_entered(player_id: String, character_data) -> void:
    # Give starter items, initialize player state, etc.
```

---

## Testing

Smoke tests live in `game/tests/`. Run with Godot headless:

```bash
cd game
godot --headless --path . --script res://tests/test_notification_toast.gd
godot --headless --path . --script res://tests/test_hud_integration.gd
godot --headless --path . --script res://tests/test_login_flow.gd
godot --headless --path . --script res://tests/test_auto_response_signals.gd
```

Or run the committed regression set (default: data-naming lint,
movement profiles, anticheat limits, blacksmith + wolf 3D probes;
`--all` = every `test_*.gd`):

```bash
sh ./scripts/godot_test_runner.sh
```

Or run all tests via Docker (see [DEPLOY.md](./DEPLOY.md)):

```bash
docker run --rm -e START_MODE=test synmergia
```

| Test | Coverage |
|------|----------|
| `test_notification_frame.gd` | NotificationService frame (context, kind, dedupe) |
| `test_notification_toast.gd` | NotificationService → TooltipManager.show_toast() end-to-end |
| `test_hud_integration.gd` | HudIntegrator handlers, NotificationService → CombatLog |
| `test_login_flow.gd` | Account + login + character flow |
| `test_auto_response_signals.gd` | AutoResponseService signals and ActionType enum |
| `test_islands.gd` | Core island logic (island_poc.gd) |
| `test_e2e_flow.gd` | End-to-end account flow |
| `test_notif_migration_*.gd` | Notification migration tests |
| `test_acts_service.gd` | ActsService: door_opened consumer, gate/fill/fence logic, voice-law check, almanac watch button, Chronicle panel, DictStore round-trip (int keys normalized on load -- JSON stringifies them) |
| `test_mysteries.gd` | Chapter-gated mysteries: data shape, gate-before-answer ordering, derived sky-code + tally answers, per-player solved ledger + reboot round-trip, TitleService reward |
| `test_audio_service.gd` | AudioService: WAVs load, pool built, unknown names rejected, round-robin advances (structural only -- headless has no audio device) |
| `test_daily_quest.gd` | quest_watch_the_sky: RECORD_INSIGHT credit per player, turn-in, REWARDED-daily reset at the sky day boundary, full re-earn loop |
| `test_blessed_mark.gd` | Blessed-class motif: sigil truth (earn-gated), GM-gold distinctness, mote-ring visuals, transition toast, title composition order |

> **Note:** `--script` mode does not pre-load autoloads. Resolve them via
> `root.get_node_or_null("NotificationService")` rather than the bare identifier.

### Test structure

Tests live in two places:

- **`game/tests/`** — smoke tests for one system each
  (login flow, notification dispatch, etc.). These run the full
  game boot and exercise real autoloads.
- **`game/tests/adapters/`** — unit and integration tests for
  the storage adapter layer. Do not require the full game boot;
  instantiate `AdapterRegistry` and backends directly.

A typical test file uses the `SceneTree` pattern:

```gdscript
extends SceneTree

func _init() -> void:
    var ok := true
    if not _test_basic_crud():
        push_error("FAIL: basic_crud")
        ok = false
    quit(0 if ok else 1)

func _test_basic_crud() -> bool:
    var store := MemoryPersistenceStore.new()
    # ... actual test ...
    return true
```

Run with `godot --headless --path . --script res://tests/test_foo.gd`.
Exit code 0 = pass, 1 = fail.

For adapter tests, use the same pattern but reference backends
through the registry:

```gdscript
extends SceneTree

func _init() -> void:
    AdapterRegistry.register("default", MemoryPersistenceStore.new())
    var store: PersistenceStore = AdapterRegistry.get("default")
    # ... exercise store ...
    quit(0)
```

When adding a new adapter backend (e.g., a new database), add a
test in `game/tests/adapters/` that:
1. Constructs the backend
2. Runs CRUD against `MemoryPersistenceStore` (the reference)
3. Verifies the new backend returns the same results

Do not test against the live database in unit tests; spin up a
test container or use the memory backend as the oracle.

### Adapter layer overview

Services should NEVER touch Postgres, Redis, or any storage
backend directly. They go through `AdapterRegistry`:

```gdscript
# In a service:
var store: PersistenceStore = AdapterRegistry.get("accounts")
await store.put(player_id, account_data)
var data = await store.get(player_id)
```

The registry returns a `PersistenceStore` (memory, Postgres, or
any other impl) based on boot configuration. See
`labs/prd-db.md` §3-5 for the full spec.

---

## Key Godot Rules

1. **Entity autoload is REQUIRED:** `Entity` must be in the
   `[autoload]` section BEFORE `RegisterTypes`. The parser needs
   `Entity` to be a known type when RegisterTypes walks the type
   tree. (Same logic for `AdapterRegistry` and `BackendFactory`:
   they must come before any service that uses them in `_ready`.)

2. **`load()` vs `preload()` vs `class_name.new()`:** pick by use
   case, not by habit.

   ```gdscript
   # Use class_name + .new() when the class is registered globally
   # (preferred for non-autoload, frequently-instantiated types):
   class_name SkillBook          # in res://core/schemas/skill_book.gd
   var book := SkillBook.new()   # works at parse time

   # Use load() + .new() when you do NOT want class_name globally
   # registered (e.g., to avoid an autoload/class_name collision,
   # or to load lazily at runtime):
   var script := load("res://core/schemas/skill_book.gd")
   var book = script.new()

   # Use preload() + .new() only when the file is constant
   # (resource path hard-coded) AND has class_name. Otherwise
   # use load(). Mixing these causes "Identifier X not declared"
   # parse errors.
   ```

3. **`extends` must precede `class_name`** in any file that has
   both. The parser reads them in order; if `class_name` comes
   first, the parse fails.

4. **Tabs only, in GDScript files.** Once a line uses a tab, every
   line in that scope must use a tab. `.editorconfig` is supposed
   to enforce this, but copy-paste from the web and shell heredocs
   frequently introduce spaces. When in doubt, run
   `cat -A file.gd | head -20` — tabs render as `^I`, spaces as ` `.

---

## GDScript 4 Gotchas

Common mistakes agents make with GDScript 4.7.2:

```gdscript
# Scene instantiation — use instantiate(), NOT .instance()
var instance := preload("res://scene.tscn").instantiate()  # Godot 4
var instance := preload("res://scene.tscn").instance()     # Godot 3, breaks in 4

# Script instantiation — load() vs preload() vs class_name
# See "Key Godot Rules" #2 above for the full decision tree.
var book := SkillBook.new()                              # class_name registered
var book := load("res://schemas/SkillBook.gd").new()     # runtime, no class_name

# Node removal — use queue_free(), NOT free()
instance.queue_free()  # safe, deferred
instance.free()        # can break children cleanup

# Null checks — always validate with is_instance_valid()
if node != null and is_instance_valid(node):  # safe
if node != null:                              # can hold stale references

# String formatting — both work in 4.7.2; pick one and be consistent
var msg := f"Hello {name}"   # f-string (Godot 4+, recommended for new code)
var msg := "Hello %s" % name # old style, still works
var msg := "Hello {0}".format([name])  # also works, rarely used

# Reserved keywords — `class_name`, `signal`, `func`, etc. cannot
# be variable names. Use `char_class_name`, `signal_name`, etc.
var class_name := "warrior"   # PARSE ERROR
var char_class_name := "warrior"  # OK
```

### New 4.7.2 strictness (the things that broke during the parse-error cascade)

- `Resource.get(key, default)` default arg was removed. Use
  `if resource.has(key): resource.get(key)` or
  `resource.get(key, null)` then null-check.
- Type inference on ternary requires explicit type. Use
  `var x: T = a if cond else b` not `var x := a if cond else b`.
- `class_name`, `signal`, `func`, `var`, `const` are reserved
  variable names. Rename to `char_class_name` etc.
- `assert(cond, "msg")` in release builds compiles to no-op; use
  for invariants only. For runtime checks that must run in
  release, use explicit `if not cond: return` or push to a logger.
- `await get_tree().process_frame` in `_ready()` is a valid
  way to defer past the autoload order; cheaper than
  `call_deferred` for one-shot deferred work.
- **Don't grep the horcrux.** `horcrux/*.svg` stones are one ~800 KB
  line of base64 ciphertext; a ripgrep-style match echoes the whole
  wall and starves the search result budget. They are listed in the
  repo-root `.ignore` (which search tools honor and git does not --
  the stone stays tracked and committed). If you must inspect the
  stone, use `vant horcrux inspect horcrux/<file>.svg` or read the
  README, never text search.

## Session hygiene (the 2026-10-13 disk-full incident — read this)

### Push to GitHub early and often

One working-tree-only incident cost a full day of terrain law work:
the file existed ONLY in the sandbox when the disk filled, and
`git checkout HEAD` restored a much older era. The law now:
- If it has been **a couple of hours** since the last push, push.
- After any sizeable law/battery step goes green, **commit and push
  immediately** — don't batch three turns' work into one uncommitted
  wedge. Freebuff's GitHub App mints the credential; nothing manual
  is needed and running `git push` normally is the whole job.

### Bound the logs

Probe/test stdout goes to /tmp and is regenerable — but it must
never be allowed to pile up:
- The test runner caps any single log file at 256 MB (`ulimit -f`):
  a runaway logger dies with SIGXFSZ (the test fails visibly, the
  disk survives) instead of eating the workspace.
- The runner sweeps `syn_*` logs older than a day at startup.
- Probes log per-CHECK, never per-tick/per-frame. A frame-loop
  print inside a headless probe is a disk bomb.
- Before any multi-hundred-KB file REPLACEMENT, check `df -h`. A
  failed str_replace mid-write once truncated the source file the
  check-out later had to restore.

