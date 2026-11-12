import Foundation

/// App language, chosen in Settings (engine setting `ui_language`), independent of the system language.
public enum Lang: String, CaseIterable, Sendable { case en, sl }

/// Every text of the native app in English and Slovenian.
public enum Strings {
    public static func text(_ key: String, _ lang: Lang) -> String {
        guard let pair = table[key] else { return key }
        return lang == .sl ? pair.1 : pair.0
    }

    /// "5 photos" / "5 fotografij" with the right Slovenian dual and plural forms.
    public static func photos(_ n: Int, _ lang: Lang) -> String {
        guard lang == .sl else { return n == 1 ? "1 photo" : "\(n) photos" }
        switch n % 100 {
        case 1: return "\(n) fotografija"
        case 2: return "\(n) fotografiji"
        case 3, 4: return "\(n) fotografije"
        default: return "\(n) fotografij"
        }
    }

    public static let table: [String: (String, String)] = [
        // window and sidebar
        "library": ("Library", "Knjižnica"),
        "allPhotos": ("All Photos", "Vse fotografije"),
        "favourites": ("Favourites", "Priljubljene"),
        "videos": ("Videos", "Videi"),
        "leftOut": ("Left Out", "Izpuščene"),
        "searchResults": ("Search Results", "Rezultati iskanja"),
        "days": ("Days", "Dnevi"),
        "trip": ("Trip", "Potovanje"),
        "noTrip": ("No trip", "Ni potovanja"),
        "newTrip": ("New Trip…", "Novo potovanje …"),
        "tripSteps": ("Trip Steps", "Koraki potovanja"),
        "tripStepsHelp": ("Times, best of each moment, events, descriptions and export, in the classic view until they move here",
                          "Čas, najboljše iz trenutka, dogodki, opisi in izvoz, v klasičnem pogledu, dokler ne pridejo sem"),
        "classicView": ("Classic View", "Klasični pogled"),
        "photo": ("photo", "fotografija"),
        "photos": ("photos", "fotografij"),
        "video": ("video", "video"),
        "noDate": ("No Date", "Brez datuma"),
        "noPlace": ("No place", "Brez kraja"),
        "notRated": ("Not rated", "Brez ocene"),
        "unknown": ("Unknown", "Neznano"),
        // toolbar
        "find": ("Find Photos", "Išči fotografije"),
        "searchPrompt": ("Sunset, ring, Florence", "Sončni zahod, prstan, Firence"),
        "alsoAs": ("also searched as", "iskano tudi kot"),
        "viewOptions": ("View Options", "Možnosti pogleda"),
        "sort": ("Sort", "Razvrsti"),
        "sort_time": ("By Time", "Po času"),
        "sort_person": ("By Person", "Po osebi"),
        "sort_place": ("By Place", "Po kraju"),
        "sort_quality": ("By Quality", "Po kakovosti"),
        "thumbSize": ("Thumbnail size", "Velikost sličic"),
        "export": ("Export…", "Izvozi …"),
        "exportHelp": ("Export for Google Photos (classic view for now)", "Izvoz za Google Photos (zaenkrat v klasičnem pogledu)"),
        "inspector": ("Inspector", "Inšpektor"),
        // photo actions
        "photoMenu": ("Photo", "Fotografija"),
        "favourite": ("Favourite", "Priljubljena"),
        "unfavourite": ("Remove Favourite", "Odstrani priljubljeno"),
        "leaveOut": ("Leave Out", "Izpusti"),
        "keep": ("Keep", "Obdrži"),
        "wallpaper": ("Phone Wallpaper", "Ozadje za telefon"),
        "quickLook": ("Quick Look", "Hitri pogled"),
        "showInFinder": ("Show in Finder", "Pokaži v Finderju"),
        "selectAll": ("Select All", "Izberi vse"),
        "selected": ("selected", "izbranih"),
        "clearSelection": ("Clear selection", "Počisti izbiro"),
        "moveToEvent": ("Move to Event", "Premakni v dogodek"),
        "newEvent": ("New Event…", "Nov dogodek …"),
        "eventName": ("Event name", "Ime dogodka"),
        "create": ("Create", "Ustvari"),
        "cancel": ("Cancel", "Prekliči"),
        // inspector
        "noSelection": ("No Selection", "Nič ni izbrano"),
        "noSelectionHint": ("Select a photo to see its details.", "Izberi fotografijo za podrobnosti."),
        "multiHint": ("Use the bar below to act on all of them.", "Z vrstico spodaj urediš vse naenkrat."),
        "taken": ("Taken", "Posneto"),
        "place": ("Place", "Kraj"),
        "noGps": ("Unknown (no GPS)", "Neznan (ni GPS)"),
        "person": ("Person", "Oseba"),
        "camera": ("Camera", "Naprava"),
        "size": ("Size", "Velikost"),
        "faces": ("Faces", "Obrazi"),
        "eyesOpen": ("Eyes open", "Oči odprte"),
        "eyesClosed": ("Eyes may be closed", "Oči morda zaprte"),
        "lookingAtCamera": ("Looking at the camera", "Gleda v kamero"),
        "lookingAway": ("Looking away", "Gleda stran"),
        "extraFrame": ("Another frame of this moment is kept", "Obdržan je drug posnetek tega trenutka"),
        "focus": ("Focus", "Ostrina"),
        "auto": ("Auto", "Samodejno"),
        "tier_sharp": ("Sharp", "Ostra"),
        "tier_soft": ("Soft", "Mehka"),
        "tier_blurry": ("Blurry", "Zamegljena"),
        "description": ("Description", "Opis"),
        "aiNote": ("Written by local AI on this Mac, not checked.", "Napisal lokalni AI na tem Macu, ni preverjeno."),
        "howTime": ("How the time was decided", "Kako je bil določen čas"),
        // empty states and engine
        "noTripsTitle": ("No Trips Yet", "Ni še potovanj"),
        "noTripsText": ("Create a trip in Trip Steps: name it and add one folder per person.",
                        "Potovanje ustvariš v Korakih potovanja: poimenuj ga in dodaj mapo za vsako osebo."),
        "nothingHere": ("Nothing Here", "Tukaj ni ničesar"),
        "nothingHereText": ("No photos match this view.", "Nobena fotografija ne ustreza temu pogledu."),
        "starting": ("Starting Photo Curator…", "Zaganjam Photo Curator …"),
        "engineFailed": ("The Engine Did Not Start", "Pogon se ni zagnal"),
        "engineUnreachable": ("The engine does not answer.", "Pogon se ne odziva."),
        "tryAgain": ("Try Again", "Poskusi znova"),
        "showLog": ("Show Engine Log", "Pokaži dnevnik pogona"),
        // activity
        "working": ("Working on your photos", "Delam na tvojih fotografijah"),
        "nothingRunning": ("Nothing is running.", "Nič ne teče."),
        "analyseAgain": ("Analyse Again", "Analiziraj znova"),
        "stop": ("Stop", "Ustavi"),
        "phase_idle": ("Up to date", "Vse je posodobljeno"),
        "phase_reading": ("Reading photos", "Berem fotografije"),
        "phase_clocks": ("Aligning clocks", "Poravnavam ure"),
        "phase_duplicates": ("Finding similar shots", "Iščem podobne posnetke"),
        "phase_quality": ("Rating focus", "Ocenjujem ostrino"),
        "phase_faces": ("Looking at faces", "Pregledujem obraze"),
        "phase_videos": ("Reading videos", "Berem videe"),
        "phase_searchIndex": ("Learning what is in the photos", "Spoznavam vsebino fotografij"),
        "phase_describing": ("Writing descriptions", "Pišem opise"),
        "phase_exporting": ("Exporting", "Izvažam"),
        "phase_paused": ("Paused to keep the Mac cool", "Premor, da se Mac ohladi"),
        "phase_working": ("Working", "Delam"),
        "phase_failed": ("Something went wrong", "Nekaj je šlo narobe"),
        // settings
        "general": ("General", "Splošno"),
        "language": ("Language", "Jezik"),
        "aiLimit": ("Local AI may use", "Lokalni AI sme uporabiti"),
        "gentle": ("Gentle (about 25 % GPU time)", "Nežno (okoli 25 % časa GPU)"),
        "standard": ("Standard (about 30 %)", "Običajno (okoli 30 %)"),
        "faster": ("Faster (about 50 %)", "Hitreje (okoli 50 %)"),
        "noLimit": ("No limit (gets warm)", "Brez omejitve (se segreje)"),
        "pauseOnBattery": ("Pause local AI on battery", "Na bateriji ustavi lokalni AI"),
        "aiLimitHint": ("Everything runs on this Mac. Nothing is uploaded.", "Vse teče na tem Macu. Nič se ne nalaga na splet."),
        "bestOfMoment": ("Best of Each Moment", "Najboljše iz trenutka"),
        "w_faces": ("Faces (eyes, gaze)", "Obrazi (oči, pogled)"),
        "w_focus": ("Focus", "Ostrina"),
        "w_look": ("Overall look", "Skupni vtis"),
        "w_resolution": ("Resolution", "Ločljivost"),
        "keeperHint": ("How much each criterion counts when the app picks the best of near-identical shots.",
                       "Koliko šteje vsako merilo, ko aplikacija izbira najboljšega med skoraj enakimi posnetki."),
    ]
}
