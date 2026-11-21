// Essais du volet de gauche à plusieurs vues (18/11/2026) : `Side --test-pages`.
// Des gestes fabriqués image par image, et la liste des vues avec des réglages à part (les vrais ne sont pas touchés).
import AppKit

enum EssaisPages {
    /// Renvoie le nombre d'essais ratés (0 : tout va bien).
    static func lancer() -> Int32 {
        var ratés: Int32 = 0
        func vérifier(_ nom: String, _ ok: Bool) {
            print(ok ? "ok    " : "RATÉ  ", nom)
            if !ok { ratés += 1 }
        }

        // Quatre doigts (ou n) qui vont de (x0, y0) à (x1, y1) en 12 images, chacun avec son petit décalage de départ.
        func trajet(_ n: Int = 4, de x0: Float, _ y0: Float, à x1: Float, _ y1: Float) -> [[(Int32, Float, Float)]] {
            (0...12).map { i in
                let t = Float(i) / 12
                return (0..<n).map { d in (Int32(d), x0 + (x1 - x0) * t + Float(d) * 0.05, y0 + (y1 - y0) * t) }
            }
        }
        // Le geste suit les doigts : (début, sens), les avancées, puis la fin (avancée, vitesse) au lever des doigts.
        func geste(_ images: [[(Int32, Float, Float)]]) -> [GestePages.Événement] {
            var t: TimeInterval = 100
            _ = GestePages.suivre([], instant: t)
            var r = images.compactMap { im -> GestePages.Événement? in t += 0.016; return GestePages.suivre(im, instant: t) }
            if let fin = GestePages.suivre([], instant: t + 0.016) { r.append(fin) }
            return r
        }
        func début(_ e: [GestePages.Événement]) -> Int? { if case .début(let s)? = e.first { return s }; return nil }
        func fin(_ e: [GestePages.Événement]) -> (Float, Float)? { if case .fin(let p, let v)? = e.last { return (p, v) }; return nil }
        func suivis(_ e: [GestePages.Événement]) -> [Float] { e.compactMap { if case .suivi(let p) = $0 { return p }; return nil } }

        let àGauche = geste(trajet(de: 0.5, 0.5, à: 0.35, 0.5))
        vérifier("quatre doigts vers la gauche : la carte suivante", début(àGauche) == 1)
        vérifier("la carte suit les doigts (avancée croissante)", suivis(àGauche).count > 3 && suivis(àGauche) == suivis(àGauche).sorted())
        vérifier("lever les doigts : fin à mi-course (0,15 / 0,3), avec élan", fin(àGauche).map { abs($0.0 - 0.5) < 0.08 && $0.1 > 0 } == true)
        vérifier("une seule fin", àGauche.filter { if case .fin = $0 { return true }; return false }.count == 1)
        vérifier("quatre doigts vers la droite : la carte précédente", début(geste(trajet(de: 0.4, 0.5, à: 0.55, 0.5))) == -1)
        vérifier("plutôt vertical : rien", geste(trajet(de: 0.4, 0.5, à: 0.5, 0.64)).isEmpty)
        vérifier("un peu en biais mais horizontal : la carte part", début(geste(trajet(de: 0.5, 0.5, à: 0.35, 0.56))) == 1)
        // Relecture du 21/11/2026 : les doigts n'arrivent pas ensemble, et l'un d'eux peut traîner au départ.
        // Trois doigts glissent déjà (5 % du trackpad) quand le quatrième se pose.
        let enRetard: [[(Int32, Float, Float)]] = (0...20).map { i in
            let x: Float = 0.6 - Float(i) * 0.01
            let n = i < 5 ? 3 : 4
            return (0..<n).map { d -> (Int32, Float, Float) in (Int32(d), x + Float(d) * 0.05, 0.5) }
        }
        vérifier("quatrième doigt posé en retard : la carte part quand même", début(geste(enRetard)) == 1)
        vérifier("quatrième doigt en retard : pas de saut au départ", (suivis(geste(enRetard)).first ?? 1) < 0.15)
        // Le petit doigt reste presque sur place les premiers millimètres, puis suit les autres.
        let traîne: [[(Int32, Float, Float)]] = (0...20).map { i in
            let t: Float = Float(i) * 0.005
            let lent: Float = max(0, t - 0.02)
            return (0..<4).map { d -> (Int32, Float, Float) in (Int32(d), 0.6 - (d == 3 ? lent : t) + Float(d) * 0.05, 0.5) }
        }
        vérifier("un doigt traîne au départ : la carte part quand même", début(geste(traîne)) == 1)
        // Glisser à trois doigts, le pouce posé sans bouger : ce n'est pas pour nous, même en insistant.
        let pouce: [[(Int32, Float, Float)]] = (0...30).map { i in
            let x: Float = 0.7 - Float(i) * 0.01
            return (0..<4).map { d -> (Int32, Float, Float) in d == 3 ? (3, 0.2, 0.1) : (Int32(d), x + Float(d) * 0.05, 0.5) }
        }
        vérifier("trois doigts et le pouce posé : rien", geste(pouce).isEmpty)
        let net = GestePages.horizontal(0.016, 0.002) == true && GestePages.horizontal(0.002, -0.016) == false
        let tôt = GestePages.horizontal(0.016, 0.012) == nil && GestePages.horizontal(0.01, 0) == nil
        let biais = GestePages.horizontal(0.035, 0.03) == true && GestePages.horizontal(0.03, 0.035) == false
        vérifier("la règle commune : net à 2 mm, en biais on attend", net && tôt && biais)
        vérifier("trois doigts seulement : rien", geste(trajet(3, de: 0.5, 0.5, à: 0.3, 0.5)).isEmpty)
        vérifier("tout petit trajet (0,01) : rien", geste(trajet(de: 0.5, 0.5, à: 0.49, 0.5)).isEmpty)
        // Pincement : deux doigts vers la gauche, deux vers la droite.
        let pincement: [[(Int32, Float, Float)]] = (0...12).map { i in
            let t = Float(i) / 12 * 0.15
            return [(0, 0.3 - t, 0.5), (1, 0.35 - t, 0.5), (2, 0.6 + t, 0.5), (3, 0.65 + t, 0.5)]
        }
        vérifier("pincement : rien", geste(pincement).isEmpty)
        // Aller puis revenir : l'avancée retombe à zéro, jamais en dessous.
        let retour = geste(trajet(de: 0.5, 0.5, à: 0.4, 0.5) + trajet(de: 0.4, 0.5, à: 0.6, 0.5))
        vérifier("revenir en arrière : l'avancée retombe à 0", suivis(retour).last == 0 && suivis(retour).allSatisfy { $0 >= 0 })
        vérifier("revenir en arrière : élan négatif à la fin", fin(retour).map { $0.1 < 0 } == true)

        // La place des deux cartes : celle de devant glisse vers le bord gauche, celle de derrière (plus petite) grandit.
        let cadre = NSRect(x: 0, y: 0, width: 500, height: 900)
        let d0 = CartesPile.disposition(cadre, avancée: 0, sens: 1)
        vérifier("au départ : la carte de devant est à sa place", d0.devant == cadre)
        vérifier("au départ : celle de derrière est plus petite et centrée",
                 d0.derrière.width < cadre.width && abs(d0.derrière.midX - cadre.midX) < 0.5 && abs(d0.derrière.midY - cadre.midY) < 0.5)
        vérifier("au départ : celle de derrière est assombrie", d0.voile > 0.2)
        let d1 = CartesPile.disposition(cadre, avancée: 1, sens: 1)
        vérifier("à l'arrivée : celle de devant est sortie par la gauche", d1.devant.maxX <= cadre.minX)
        vérifier("à l'arrivée : celle de derrière a pris la place", d1.derrière == cadre && d1.voile == 0)
        let r0 = CartesPile.disposition(cadre, avancée: 0, sens: -1)
        let r1 = CartesPile.disposition(cadre, avancée: 1, sens: -1)
        vérifier("vers la précédente : elle revient du bord gauche par-dessus", r0.devant.maxX <= cadre.minX && r1.devant == cadre)
        vérifier("vers la précédente : la carte en cours recule derrière", r0.derrière == cadre && r1.derrière.width < cadre.width)
        vérifier("la carte de devant sort entièrement, marge du bord comprise", d1.devant.maxX <= cadre.minX - 12)
        let flottant = VoletVue.flottant(NSRect(x: 0, y: 0, width: 520, height: 900))
        vérifier("le volet flotte : un peu de bord à gauche, en haut et en bas",
                 flottant.minX == 10 && flottant.minY == 10 && flottant.maxY == 890 && flottant.width == 520)
        // À droite, tout est en miroir : la carte de devant sort par la droite, la marge est à droite.
        let dd = CartesPile.disposition(cadre, avancée: 1, sens: 1, droite: true)
        vérifier("à droite : la carte de devant sort par la droite", dd.devant.minX >= cadre.maxX + 12 && dd.derrière == cadre)
        let rd = CartesPile.disposition(cadre, avancée: 0, sens: -1, droite: true)
        vérifier("à droite : la précédente revient du bord droit", rd.devant.minX >= cadre.maxX)
        let flottantD = VoletVue.flottant(NSRect(x: 1000, y: 0, width: 520, height: 900), droite: true)
        vérifier("à droite : le bord est à droite", flottantD.maxX == 1510 && flottantD.minY == 10 && flottantD.width == 520)
        vérifier("à droite : l'élastique part vers la droite", CartesPile.élastique(cadre, avancée: 1, sens: 1, droite: true).minX > cadre.minX)
        let b = CartesPile.élastique(cadre, avancée: 1, sens: 1)
        vérifier("au bout de la liste : la carte bouge un peu, sans partir", b.minX < cadre.minX && b.minX > cadre.minX - 80)

        // La liste des vues, avec des réglages à part.
        let nom = "com.gauthieraube.side.essai-pages"
        guard let d = UserDefaults(suiteName: nom) else { return ratés + 1 }
        d.removePersistentDomain(forName: nom)
        let p = PileVues(défauts: d, côté: .gauche)
        p.vues = ["/A.app", "/B.app", "/C.app"]
        p.index = 2
        vérifier("au bout : la suivante est la 1re (roulement sans fin)", p.page(1) == 0)
        vérifier("au bout : la précédente est la 2e", p.page(-1) == 1)
        p.index = 0
        vérifier("au début : la précédente est la dernière (roulement sans fin)", p.page(-1) == 2)
        vérifier("vue en cours = la 1re", p.cheminCourant == "/A.app")
        p.index = 2
        p.vues = ["/A.app"]
        vérifier("liste réduite à une vue : on revient à la 1re", p.index == 0)
        vérifier("une seule vue : pas de voisine", p.page(1) == nil && p.page(-1) == nil)
        p.vues = []
        vérifier("liste vide : pas de vue en cours", p.cheminCourant == nil && p.page(1) == nil)
        p.vues = ["/A.app", "/B.app"]
        p.index = 1
        let relue = PileVues(défauts: d, côté: .gauche)
        vérifier("la liste et la vue en cours sont retenues", relue.vues == ["/A.app", "/B.app"] && relue.index == 1)
        vérifier("largeur par défaut 520", relue.largeur == 520)
        // À droite : une liste à part, rangée sous d'autres clés.
        let droite = PileVues(défauts: d, côté: .droite)
        vérifier("la liste de droite est à part", droite.vues.isEmpty)
        droite.vues = ["/D.app"]
        vérifier("la liste de gauche ne bouge pas", PileVues(défauts: d, côté: .gauche).vues == ["/A.app", "/B.app"])
        vérifier("chaque côté a sa valeur de coin", PileVues.gauche.sentinelle == "pile:gauche" && PileVues.droite.sentinelle == "pile:droite")
        vérifier("une valeur de coin retrouve sa liste", PileVues.pour("pile:droite") === PileVues.droite && PileVues.pour("/X.app") == nil)
        d.removePersistentDomain(forName: nom)

        // Relecture : les fenêtres des vues retirées des réglages reviennent à l'écran (sauf celle affichée).
        vérifier("vue retirée : sa fenêtre revient",
                 VoletVue.retirées(avant: ["/A.app", "/B.app", "/C.app"], après: ["/A.app", "/C.app"], affiché: nil) == ["/B.app"])
        vérifier("vue retirée mais affichée : elle reste pour l'instant",
                 VoletVue.retirées(avant: ["/A.app", "/B.app"], après: ["/A.app"], affiché: "/B.app") == [])
        // Relecture : avec plusieurs bureaux, c'est macOS qui prend le geste (sauf si Square le prend toujours).
        vérifier("un seul bureau : le geste est au volet", VoletVue.gesteLibre(bureaux: 1, toujours: false, systèmeLibre: false))
        vérifier("plusieurs bureaux : le geste est à macOS", !VoletVue.gesteLibre(bureaux: 3, toujours: false, systèmeLibre: false))
        vérifier("plusieurs bureaux, geste de macOS coupé : au volet", VoletVue.gesteLibre(bureaux: 3, toujours: false, systèmeLibre: true))
        vérifier("plusieurs bureaux, « toujours » : au volet", VoletVue.gesteLibre(bureaux: 3, toujours: true, systèmeLibre: false))
        return ratés
    }
}
