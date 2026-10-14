import Foundation

/// Kwota słownie na fakturze: „tysiąc dwieście trzydzieści cztery złote 56/100”.
public enum AmountInWords {
    public static func polish(_ amount: Decimal, currency: String) -> String {
        let (whole, cents, negative) = split(amount)
        let forms = polishCurrency[currency.uppercased()]
        var words = whole == 0 ? "zero" : polishNumber(whole)
        if negative { words = "minus " + words }
        let unit = forms.map { pick(whole, $0) } ?? currency.uppercased()
        return "\(words) \(unit) \(String(format: "%02d", cents))/100"
    }

    public static func english(_ amount: Decimal, currency: String) -> String {
        let (whole, cents, negative) = split(amount)
        var words = whole == 0 ? "zero" : englishNumber(whole)
        if negative { words = "minus " + words }
        return "\(words) \(currency.uppercased()) \(String(format: "%02d", cents))/100"
    }

    static func split(_ amount: Decimal) -> (whole: Int64, cents: Int, negative: Bool) {
        let minor = amount.minorUnits
        return (Int64(minor.magnitude / 100), Int(minor.magnitude % 100), minor < 0)
    }

    // MARK: Polski

    static let polishCurrency: [String: (String, String, String)] = [
        "PLN": ("złoty", "złote", "złotych"),
        "EUR": ("euro", "euro", "euro"),
        "USD": ("dolar", "dolary", "dolarów"),
        "GBP": ("funt", "funty", "funtów"),
        "CHF": ("frank", "franki", "franków"),
    ]

    static let units = ["", "jeden", "dwa", "trzy", "cztery", "pięć", "sześć", "siedem", "osiem", "dziewięć"]
    static let teens = ["dziesięć", "jedenaście", "dwanaście", "trzynaście", "czternaście", "piętnaście",
                        "szesnaście", "siedemnaście", "osiemnaście", "dziewiętnaście"]
    static let tens = ["", "", "dwadzieścia", "trzydzieści", "czterdzieści", "pięćdziesiąt",
                       "sześćdziesiąt", "siedemdziesiąt", "osiemdziesiąt", "dziewięćdziesiąt"]
    static let hundreds = ["", "sto", "dwieście", "trzysta", "czterysta", "pięćset",
                           "sześćset", "siedemset", "osiemset", "dziewięćset"]
    static let scales: [(String, String, String)] = [
        ("", "", ""), ("tysiąc", "tysiące", "tysięcy"), ("milion", "miliony", "milionów"),
        ("miliard", "miliardy", "miliardów"), ("bilion", "biliony", "bilionów"),
    ]

    /// Forma liczebnika: 1 → pierwsza, 2–4 (bez 12–14) → druga, reszta → trzecia.
    static func pick(_ n: Int64, _ forms: (String, String, String)) -> String {
        if n == 1 { return forms.0 }
        let last = n % 10, lastTwo = n % 100
        return (2...4).contains(last) && !(12...14).contains(lastTwo) ? forms.1 : forms.2
    }

    static func polishBelowThousand(_ n: Int) -> [String] {
        var parts = [hundreds[n / 100]]
        let rest = n % 100
        if (10...19).contains(rest) {
            parts.append(teens[rest - 10])
        } else {
            parts += [tens[rest / 10], units[rest % 10]]
        }
        return parts.filter { !$0.isEmpty }
    }

    static func polishNumber(_ n: Int64) -> String {
        var groups: [Int] = []
        var rest = n
        while rest > 0 { groups.append(Int(rest % 1000)); rest /= 1000 }
        var words: [String] = []
        for (scale, group) in groups.enumerated().reversed() where group > 0 {
            if scale == 0 {
                words += polishBelowThousand(group)
            } else if group == 1 {
                words.append(scales[scale].0)
            } else {
                words += polishBelowThousand(group)
                words.append(pick(Int64(group), scales[scale]))
            }
        }
        return words.joined(separator: " ")
    }

    // MARK: English

    static let englishUnits = ["", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
                               "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"]
    static let englishTens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    static let englishScales = ["", "thousand", "million", "billion", "trillion"]

    static func englishBelowThousand(_ n: Int) -> String {
        var parts: [String] = []
        if n >= 100 { parts.append("\(englishUnits[n / 100]) hundred") }
        let rest = n % 100
        if rest >= 20 {
            parts.append(rest % 10 == 0 ? englishTens[rest / 10] : "\(englishTens[rest / 10])-\(englishUnits[rest % 10])")
        } else if rest > 0 {
            parts.append(englishUnits[rest])
        }
        return parts.joined(separator: " ")
    }

    static func englishNumber(_ n: Int64) -> String {
        var groups: [Int] = []
        var rest = n
        while rest > 0 { groups.append(Int(rest % 1000)); rest /= 1000 }
        return groups.enumerated().reversed().filter { $0.element > 0 }.map { scale, group in
            [englishBelowThousand(group), englishScales[scale]].filter { !$0.isEmpty }.joined(separator: " ")
        }.joined(separator: " ")
    }
}
