import Foundation

struct UmbrellaGenres {
    
    /// Normalize genre strings for lookup
    /// Handles parentheses, hyphens, spaces, and other variations
    static func normalize(_ genre: String) -> String {
        var normalized = genre
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove content in parentheses (e.g., "techno (peak time" -> "techno")
        if let parenRange = normalized.range(of: "(") {
            normalized = String(normalized[..<parenRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Remove trailing punctuation and parentheses
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}.,;:!?"))
        
        // Normalize hyphens and spaces (treat hyphens as spaces for matching)
        normalized = normalized.replacingOccurrences(of: "-", with: " ")
        normalized = normalized.replacingOccurrences(of: ".", with: " ")
        normalized = normalized.replacingOccurrences(of: "&", with: "and")
        
        // Collapse multiple spaces
        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        // Remove diacritics and trim again
        normalized = normalized.folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return normalized
    }

    /// Look up umbrella genre (default: "Unknown")
    /// Normalization handles parentheses, hyphens, and other variations
    static func resolve(_ rawGenre: String) -> String {
        let key = normalize(rawGenre)
        return map[key] ?? "Unknown"
    }
    
    /// Split comma-separated genre strings into individual genres
    /// Handles cases where Jellyfin returns "techno, electro, minimal" as a single string
    static func splitGenres(_ genres: [String]) -> [String] {
        return genres.flatMap { genreString in
            genreString
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }
    
    /// Classify multiple genres and return raw, normalized, and umbrella arrays
    /// Automatically splits comma-separated genre strings
    static func classifyGenres(_ genres: [String]) -> (raw: [String], normalized: [String], umbrella: [String]) {
        // First split any comma-separated genres
        let splitGenres = Self.splitGenres(genres)
        let raw = splitGenres
        let normalized = splitGenres.map { normalize($0) }
        let umbrella = splitGenres.map { resolve($0) }
        return (raw: raw, normalized: normalized, umbrella: umbrella)
    }

    /// Umbrella genre mapping
    static let map: [String: String] = [
        // Electronic family
        "acid house": "Electronic",
        "acid jazz": "Electronic",
        "acid techno": "Electronic",
        "acid trance": "Electronic",
        "acidcore": "Electronic",
        "acid breaks": "Electronic",
        "afro house": "Electronic",
        "ambient": "Electronic",
        "ambient dub": "Electronic",
        "ambient techno": "Electronic",
        "ambient trance": "Electronic",
        "bass": "Electronic",
        "bass music": "Electronic",
        "breakbeat": "Electronic",
        "breaks": "Electronic",
        "big beat": "Electronic",
        "chillout": "Electronic",
        "chillwave": "Electronic",
        "club": "Electronic",
        "dance": "Electronic",
        "darkstep": "Electronic",
        "deep house": "Electronic",
        "disco house": "Electronic",
        "downtempo": "Electronic",
        "drum & bass": "Electronic",
        "drum n bass": "Electronic",
        "drum and bass": "Electronic",
        "dnb": "Electronic",
        "d'n'b": "Electronic",
        "dub": "Electronic",
        "dub techno": "Electronic",
        "dubstep": "Electronic",
        "edm": "Electronic",
        "electro": "Electronic",
        "electro house": "Electronic",
        "electronica": "Electronic",
        "electronic": "Electronic",
        "electronique": "Electronic",
        "experimental electronic": "Electronic",
        "future bass": "Electronic",
        "future house": "Electronic",
        "garage": "Electronic",
        "grime": "Electronic",
        "hard house": "Electronic",
        "hard trance": "Electronic",
        "hardcore": "Electronic",
        "hardcore breaks": "Electronic",
        "hardstyle": "Electronic",
        "house": "Electronic",
        "idm": "Electronic",
        "industrial": "Electronic",
        "jungle": "Electronic",
        "jump up": "Electronic",
        "liquid funk": "Electronic",
        "melodic house": "Electronic",
        "melodic house and techno": "Electronic",
        "melodic techno": "Electronic",
        "minimal": "Electronic",
        "minimal techno": "Electronic",
        "minimal tech house": "Electronic",
        "neurofunk": "Electronic",
        "peak time techno": "Electronic",
        "progressive house": "Electronic",
        "progressive trance": "Electronic",
        "psybient": "Electronic",
        "psytrance": "Electronic",
        "synthwave": "Electronic",
        "tech house": "Electronic",
        "techno": "Electronic",
        "trance": "Electronic",
        "uk garage": "Electronic",
        "vaporwave": "Electronic",
        "dancefloor drum and bass": "Electronic",
        "ambient house": "Electronic",
        "atmospheric drum and bass": "Electronic",
        "bass house": "Electronic",
        "big room house": "Electronic",
        "breakbeat hardcore": "Electronic",
        "breakcore": "Electronic",
        "breakstep": "Electronic",
        "brostep": "Electronic",
        "chillstep": "Electronic",
        "complextro": "Electronic",
        "dark ambient": "Electronic",
        "drumstep": "Electronic",
        "electroclash": "Electronic",
        "electropop": "Electronic",
        "fidget house": "Electronic",
        "glitch": "Electronic",
        "glitch hop": "Electronic",
        "happy hardcore": "Electronic",
        "liquid drum and bass": "Electronic",
        "speedcore": "Electronic",
        "techstep": "Electronic",

        // Rock family
        "alternative": "Rock",
        "alternative rock": "Rock",
        "alternative metal": "Rock",
        "art rock": "Rock",
        "blues rock": "Rock",
        "classic rock": "Rock",
        "garage rock": "Rock",
        "glam rock": "Rock",
        "hard rock": "Rock",
        "indie rock": "Rock",
        "math rock": "Rock",
        "nu metal": "Rock",
        "pop.rock": "Rock",
        "post-hardcore": "Rock",
        "progressive rock": "Rock",
        "psychedelic rock": "Rock",
        "rock": "Rock",
        "soft rock": "Rock",
        "stoner rock": "Rock",
        "symphonic rock": "Rock",
        "acid rock": "Rock",
        "acoustic rock": "Rock",
        "arena rock": "Rock",
        "country rock": "Rock",
        "dance-rock": "Rock",
        "deathrock": "Rock",
        "desert rock": "Rock",
        "electronic rock": "Rock",
        "folk rock": "Rock",
        "gothic rock": "Rock",
        "noise rock": "Rock",
        "post-rock": "Rock",
        "shoegaze": "Rock",
        "southern rock": "Rock",
        "surf rock": "Rock",
        "yacht rock": "Rock",

        // Punk
        "punk": "Punk",
        "pop punk": "Punk",
        "anarcho-punk": "Punk",
        "ska punk": "Punk",
        "crust punk": "Punk",
        "d-beat": "Punk",
        "hardcore punk": "Punk",
        "oi!": "Punk",
        "post-punk": "Punk",

        // Metal family
        "metal": "Metal",
        "black metal": "Metal",
        "death metal": "Metal",
        "doom metal": "Metal",
        "folk metal": "Metal",
        "heavy metal": "Metal",
        "industrial metal": "Metal",
        "melodic death metal": "Metal",
        "metalcore": "Metal",
        "power metal": "Metal",
        "progressive metal": "Metal",
        "speed metal": "Metal",
        "thrash metal": "Metal",
        "atmospheric black metal": "Metal",
        "blackened death metal": "Metal",
        "brutal death metal": "Metal",
        "deathcore": "Metal",
        "drone metal": "Metal",
        "funeral doom metal": "Metal",
        "gothic metal": "Metal",
        "groove metal": "Metal",
        "melodic black metal": "Metal",
        "post-metal": "Metal",
        "sludge metal": "Metal",
        "symphonic metal": "Metal",

        // Hip-Hop family
        "abstract hip hop": "Hip-Hop",
        "alternative hip hop": "Hip-Hop",
        "aussie hip-hop": "Hip-Hop",
        "boom bap": "Hip-Hop",
        "conscious hip hop": "Hip-Hop",
        "dirty south": "Hip-Hop",
        "east coast hip hop": "Hip-Hop",
        "gangsta rap": "Hip-Hop",
        "g-funk": "Hip-Hop",
        "hip hop": "Hip-Hop",
        "hiphop": "Hip-Hop",
        "mc raggamuffin hip-hop": "Hip-Hop",
        "pop rap": "Hip-Hop",
        "rap": "Hip-Hop",
        "rap and hip-hop": "Hip-Hop",
        "trap": "Hip-Hop",
        "trip hop": "Hip-Hop",
        "turntablism": "Hip-Hop",
        "west coast hip hop": "Hip-Hop",
        "cloud rap": "Hip-Hop",
        "drill": "Hip-Hop",
        "emo rap": "Hip-Hop",
        "experimental hip hop": "Hip-Hop",
        "hardcore hip hop": "Hip-Hop",
        "mumble rap": "Hip-Hop",
        "phonk": "Hip-Hop",
        "plugg nb": "Hip-Hop",
        "rage": "Hip-Hop",
        "soundcloud rap": "Hip-Hop",
        "trap metal": "Hip-Hop",

        // R&B / Soul
        "r&b": "R&B",
        "funk": "R&B",
        "neo soul": "R&B",
        "soul": "R&B",
        "contemporary r&b": "R&B",
        "contemporary r and b": "R&B",
        "deep funk": "R&B",
        "motown": "R&B",
        "quiet storm": "R&B",
        "southern soul": "R&B",

        // Pop family
        "pop": "Pop",
        "alternative pop": "Pop",
        "chamber pop": "Pop",
        "country pop": "Pop",
        "dance pop": "Pop",
        "indie pop": "Pop",
        "j-pop": "Pop",
        "jpop": "Pop",
        "k-pop": "Pop",
        "synthpop": "Pop",
        "art pop": "Pop",
        "baroque pop": "Pop",
        "bedroom pop": "Pop",
        "britpop": "Pop",
        "bubblegum pop": "Pop",
        "dream pop": "Pop",
        "jangle pop": "Pop",
        "new wave": "Pop",
        "power pop": "Pop",

        // Blues
        "blues": "Blues",
        "acoustic blues": "Blues",
        "chicago blues": "Blues",
        "delta blues": "Blues",
        "electric blues": "Blues",
        "texas blues": "Blues",

        // Classical family
        "classical": "Classical",
        "baroque": "Classical",
        "classique": "Classical",
        "concerto": "Classical",
        "concertos pour clavier": "Classical",
        "musique concertante": "Classical",
        "opera": "Classical",
        "romantic": "Classical",
        "romantic classical": "Classical",
        "symphonic": "Classical",
        "chamber music": "Classical",
        "chamber": "Classical",
        "medieval": "Classical",
        "renaissance": "Classical",
        "sonata": "Classical",
        "symphony": "Classical",

        // Folk / Acoustic
        "folk": "Folk",
        "acoustic": "Folk",
        "singer-songwriter": "Folk",
        "alternative folk": "Folk",
        "appalachian folk": "Folk",
        "celtic folk": "Folk",
        "contemporary folk": "Folk",
        "indie folk": "Folk",
        "traditional folk": "Folk",

        // Country family
        "country": "Country",
        "bluegrass": "Country",
        "americana": "Country",
        "alternative country": "Country",
        "honky tonk": "Country",
        "outlaw country": "Country",
        "texas country": "Country",

        // Jazz family
        "jazz": "Jazz",
        "bebop": "Jazz",
        "fusion": "Jazz",
        "j-fusion": "Jazz",
        "jazz fusion": "Jazz",
        "smooth jazz": "Jazz",
        "afro-cuban jazz": "Jazz",
        "avant-garde jazz": "Jazz",
        "cool jazz": "Jazz",
        "free jazz": "Jazz",
        "gypsy jazz": "Jazz",
        "hard bop": "Jazz",
        "latin jazz": "Jazz",
        "swing": "Jazz",
        "vocal jazz": "Jazz",

        // Reggae family
        "reggae": "Reggae",
        "reggea": "Reggae",
        "ragga": "Reggae",
        "roots reggae": "Reggae",
        "ska": "Reggae",
        "dancehall": "Reggae",
        "lovers rock": "Reggae",
        "rocksteady": "Reggae",

        // Latin family
        "latin": "Latin",
        "reggaeton": "Latin",
        "salsa": "Latin",
        "bachata": "Latin",
        "cumbia": "Latin",
        "bossa nova": "Latin",
        "merengue": "Latin",
        "samba": "Latin",
        "tango": "Latin",

        // Soundtrack
        "soundtrack": "Soundtrack",
        "ost": "Soundtrack",
        "video game music": "Soundtrack",

        // World family
        "world": "World",
        "afrobeat": "World",
        "afrobeats": "World",
        "asian music": "World",
        "asie": "World",
        "japon": "World",
        "j-rock": "World",
        "klezmer": "World",
        "musiques du monde": "World",
        "bhangra": "World",
        "fado": "World",
        "flamenco": "World",
        "gamelan": "World",
        "qawwali": "World",
        "raï": "World",

        // Unknown fallback
        "unknown": "Unknown",
        "": "Unknown"
    ]
}

