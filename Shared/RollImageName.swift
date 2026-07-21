import Foundation

/// Asset catalog roll canister art — mirrors `FilmStock.rollImageName`.
enum RollImageName {
    static func resolve(stockName: String, manufacturer: String) -> String? {
        let upper = stockName.uppercased()

        if upper.contains("BERGGER") || upper.contains("PANCRO") { return "roll_bergger_pancro" }
        if upper.contains("STREETPAN") || manufacturer == "JCH" { return "roll_jch_streetpan" }
        if upper.contains("KOSMO") { return "roll_kosmo_foto_mono" }
        if upper.contains("OPTIMONO") || manufacturer == "Optikoldschool" { return "roll_optimono" }
        if upper.contains("WASHI") { return "roll_film_washi" }
        if upper.contains("SHANGHAI") || upper.contains("GP3") { return "roll_shanghai_gp3" }
        if upper.contains("ARISTA") { return "roll_arista_edu_ultra" }
        if upper.contains("ULTRAFINE") { return "roll_ultrafine_extreme" }
        if upper.contains("EFKE") { return "roll_efke_kb25" }
        if upper.contains("FOMAPAN") || manufacturer == "Foma" { return "roll_fomapan" }
        if upper.contains("FERRANIA") || manufacturer == "Ferrania" { return "roll_ferrania" }
        if upper.contains("ORWO") || manufacturer == "ORWO" { return "roll_orwo" }
        if upper.contains("ADOX") || manufacturer == "Adox" { return "roll_adox" }
        if upper.contains("HARMAN") || manufacturer == "Harman" { return "roll_harman" }

        if manufacturer == "CineStill" || upper.contains("CINESTILL") {
            if upper.contains("800T") || upper.contains("800 T") { return "roll_cinestill_800t" }
            if upper.contains("400D") || upper.contains("400 D") { return "roll_cinestill_400d" }
            if upper.contains("50D") || upper.contains("50 D") { return "roll_cinestill_50d" }
            return "roll_cinestill_400d"
        }

        switch manufacturer {
        case "Kodak": return "roll_kodak"
        case "Fujifilm": return "roll_fujifilm"
        case "Ilford": return "roll_ilford"
        case "Rollei": return "roll_rollei"
        case "Agfa": return "roll_agfa"
        case "Lomography": return "roll_lomography"
        case "Konica": return "roll_konica_centuria"
        case "Leica": return "roll_leica"
        default: return nil
        }
    }
}
