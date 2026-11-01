# Analyse de Folder Preview et cahier de reproduction

Analyse publique effectuée le 1 novembre 2026. La cible est **Folder Preview standard**, identifiant App Store `6698876601`. L’utilisateur a choisi de travailler uniquement avec les pages et captures publiques. L’application originale n’est pas installée et n’a pas été exécutée ou décompilée pendant cette analyse.

## Sources et degré de certitude

- [Page officielle d’Anybox](https://anybox.ltd/folder-preview) : description, formats annoncés et distinction standard/Pro.
- [Fiche App Store US](https://apps.apple.com/us/app/folder-preview/id6698876601?mt=12) : description et historique ; elle affiche la version 3.1.1 au moment de l’étude.
- [Grille claire](https://anybox.ltd/_next/static/media/fp-hero.2t0g0i4y9mvrt.png), [grille sombre](https://anybox.ltd/_next/static/media/fp-hero-dark.3b95269z9-7ou.png).
- [Liste de dossier](https://anybox.ltd/_next/static/media/fp-feature-1.04dmxnqn9co3b.png), [archive](https://anybox.ltd/_next/static/media/fp-feature-2.2rp6r4xur-u3b.png), [menu de colonnes](https://anybox.ltd/_next/static/media/fp-feature-3.2-hbiy5u9gjit.png), [menu de copie](https://anybox.ltd/_next/static/media/fp-feature-4.1wqp7n_5vrt7m.png).

« Observé » signifie visible dans une capture. « Annoncé » désigne une fonction mentionnée dans les pages. Les choix de code et de limites de ressources décrits ensuite sont ceux de cette réimplémentation ; ils ne constituent pas une découverte du code d’Anybox.

## Produit et parcours observables

Le produit ajoute un fournisseur Quick Look pour les dossiers et archives. Le parcours public est : activation de l’extension dans macOS, sélection dans le Finder, Espace ou ⌘Y. Le contenu s’inscrit dans la fenêtre Quick Look ; les commandes de fermeture, de plein écran, de partage et d’ouverture associée appartiennent au système. L’usage dans des gestionnaires de fichiers tiers est annoncé, mais n’a pas été testé ici. [Source officielle](https://anybox.ltd/folder-preview).

Les fonctions Pro — notamment l’ouverture externe et le glisser-déposer — sont distinguées par l’éditeur. Le brief vise la version standard liée par l’utilisateur. Une navigation interne à la prévisualisation ne doit pas être confondue avec l’ouverture d’un dossier dans Finder.

## Lecture visuelle des captures

La zone centrale occupe la largeur disponible. Il y a deux présentations : liste arborescente et grille. Le contenu ne comporte ni tableau de bord ni panneau de lecture latéral permanent.

La liste montre des chevrons de dépliage, une petite icône par ligne, des noms tronqués au milieu et des bandes alternées discrètes. Les informations secondaires sont grises. Les enfants apparaissent sous leur dossier, avec une indentation. Le tri est porté par l’en-tête. La liste se prolonge jusqu’au pied de fenêtre.

La grille donne la priorité aux miniatures et aux icônes système. Une surface claire arrondie encadre l’image ; le nom est centré, limité visuellement à deux lignes. Une information bleue suit le nom : dimensions pour les images, taille pour d’autres fichiers, nombre d’éléments pour un dossier. La sélection du nom est bleue ; la grille se redistribue avec la largeur.

Le pied de fenêtre présente un chemin sous forme de composants, puis une rangée avec un bouton d’options à gauche et le total au centre. La grille ajoute un curseur de taille à droite. Le chrome gris/translucide et les contrôles suivent l’apparence système. Les proportions peuvent être estimées à partir des images ; les valeurs exactes en points, les animations et les métriques typographiques de l’original ne sont pas établies par ces seules captures.

## Matrice de correspondance

| Élément de la référence | Preuve publique | Réimplémentation |
| --- | --- | --- |
| Espace / ⌘Y, fenêtre Quick Look | Description | Extension système réelle |
| Dossiers | Description et captures | Énumération locale progressive |
| Liste avec sous-dossiers dépliables | Capture de liste | NSOutlineView |
| Grille de miniatures | Captures de grille | NSCollectionView |
| Nom, modification, taille, type | Capture de liste | Colonnes natives |
| Création, ouverture, ajout | Menu des colonnes | Métadonnées URL lorsqu’elles existent |
| Commentaires, tags, dimensions | Menu des colonnes | Spotlight, tags Finder, ImageIO |
| Colonnes masquables | Menu des colonnes | Clic droit sur les en-têtes |
| Tri et redimensionnement | Liste / historique | En-têtes natifs, ordre/largeurs mémorisés |
| Chemin en bas | Toutes les captures | NSPathControl |
| Total taille et éléments | Captures | Calcul asynchrone, résultat partiel signalé |
| Taille des icônes | Capture de grille | Curseur inférieur mémorisé |
| Images, SVG, PDF | Description / captures | Fournisseurs système de miniatures |
| Vidéos et autres formats système | Page / historique | QuickLookThumbnailing, repli sur icône |
| Copier / copier le chemin | Capture de menu | Menu contextuel et raccourcis natifs |
| ZIP, TAR, GZ, BZ2, XZ, 7z, RAR | Page / historique | Bibliothèque libarchive système |
| Réglages de texte et de lignes | Historique | Menu d’options |
| Dossiers en premier | Historique | Option de tri |
| Dossiers ignorés | Historique | Sélection d’un dossier, puis menu d’exclusion |
| Exceptions pour les paquets applicatifs | Historique | Paquets non dépliés ; tailles omises dans /Applications |
| Apparences claire et sombre | Captures | Couleurs et matériaux AppKit adaptatifs |
| Langues multiples | Fiche App Store | Libellés français ; autres traductions non reproduites |
| macOS 12+ pour l’original | Fiche App Store | macOS 14+ pour cette intégration Droppy |

La matrice indique une correspondance fonctionnelle, pas une identité certifiée avec l’application originale. Le contenu exact des panneaux de réglages, leurs valeurs par défaut et certains comportements de bord ne sont pas publiquement observables. Les tests de notre code sont consignés dans `VALIDATION.md`.

## Architecture retenue pour Droppy

Un droplet est une bibliothèque chargée par Droppy. Une extension Quick Look est un composant distinct enregistré auprès de macOS. Le produit associe donc :

1. un `.droplet` avec réglages natifs Droppy et bouton d’installation ;
2. une petite application hôte, incluse au bundle, contenant le `.appex` ;
3. une extension sandboxée qui rend les deux vues dans Quick Look.

L’application hôte n’est pas un gestionnaire de fichiers supplémentaire. Elle sert à l’activation et au dossier de démonstration. Les options de rendu se règlent dans le menu inférieur de Quick Look et sont conservées dans les préférences de l’extension. La désactivation du droplet et celle de l’extension sont distinctes.

Le composant de rendu emploie les contrôles AppKit publics : NSOutlineView, NSCollectionView, NSPathControl, NSMenu, NSSlider et NSVisualEffectView. Les miniatures sont demandées à QuickLookThumbnailing ; aucun lecteur Web ou moteur de scripts n’est injecté dans l’aperçu. Les PDF sélectionnés directement dans Finder conservent leur fournisseur système.

## Traitement des données et contraintes choisies

L’énumération et les totaux s’effectuent hors du thread principal. Les sous-dossiers ne sont chargés dans la liste qu’à leur dépliage. Les totaux sont calculés séparément, avec annulation et bornes de profondeur, durée et nombre d’éléments. Un résultat partiel est identifié au lieu d’être présenté comme exhaustif. Les liens symboliques ne sont pas suivis et les fichiers cloud non téléchargés ne sont pas récupérés pour fabriquer une miniature.

L’index d’une archive construit les dossiers virtuels et les agrégats de tailles. Les chemins absolus, traversées et liens sont exclus. Une entrée sélectionnée peut être lue dans une limite bornée. Copier un fichier depuis une archive nécessite sa matérialisation dans un cache privé ; le presse-papiers reçoit alors une véritable URL de fichier. Le cache de copie est conservé temporairement, car un collage peut suivre la fermeture de Quick Look. Cette politique propre au droplet n’est pas attribuée à Folder Preview.

Aucun fichier source n’est modifié. Le produit n’ajoute ni télémétrie, ni serveur réseau, ni indexation permanente, ni interception globale du clavier. Les seules écritures concernent les préférences et caches nécessaires aux aperçus/copies.

## Vérification de fidélité

La comparaison utilise les captures officielles comme référence de disposition : pleine largeur, deux modes, arborescence, colonnes, chemin et commandes inférieures. Les fichiers de démonstration et l’icône du droplet sont propres au projet ; les illustrations de l’éditeur ne sont pas embarquées dans le produit.

Les contrôles automatisés vérifient la structure de l’interface, les réglages, le rendu des deux modes et les formats de fichiers. Les contrôles Quick Look doivent aussi prouver que macOS invoque réellement l’extension sur un dossier et une archive. Le harness Droppy vérifie séparément le panneau de réglages et son activation.

Une validation sur les pages publiques ne permet pas de certifier une copie « complètement identique » dans tous les cas : formats chiffrés, mots de passe, archives multi-volumes, événements de clavier, valeurs cachées, moteurs internes, conflits entre fournisseurs et gestionnaires tiers restent à comparer avec l’original pour une telle affirmation. Ces points ne sont pas inventés pour compléter artificiellement la liste.
