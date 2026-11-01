# Validation de la livraison 1.0.0

Validation effectuée le 1 novembre 2026 sur macOS 26.5, Xcode 26.6. Droppy installé : 16.2.0-beta.3 ; SDK verrouillé : DroppyKit 1.20.1. Les exécutables livrés contiennent arm64 et x86_64. L’exécution a été vérifiée sur Apple Silicon ; la tranche Intel est compilée et inspectée, sans test sur un Mac Intel physique.

| Contrôle | Résultat |
| --- | --- |
| Moteur, archives et sécurité des chemins | 37 vérifications réussies |
| Interface native claire | 9 contrôles réussis |
| Interface native sombre | 9 contrôles réussis |
| Quick Look — dossier racine | 11 éléments directs chargés |
| Quick Look — Documents | 4 éléments directs chargés |
| Quick Look — ZIP | 3 éléments directs chargés |
| Validation officielle DroppyKit | Manifeste, icône, avatar, liaison, API et architectures conformes |
| Harness DroppyKit | Activation active, erreur nulle, problèmes vides |
| Droppy Playground | Bundle effectivement chargé ; activation journalisée |
| Signature des paquets | Ad hoc, vérification profonde et stricte réussie avant archivage |

Les tests du moteur couvrent les chemins dangereux, liens, visibilité, exclusions, tri naturel, tailles, lecture seule, lecture/copie d’archives, limites et annulation. Les fixtures décodées couvrent ZIP, TAR, TAR+GZIP, TAR+BZIP2, TAR+XZ, 7z LZMA, RAR classique et RAR5 compressé. Cela ne certifie pas toutes les variantes de ces formats.

Les contrôles natifs portent sur le chargement, le dépliage sur place, le chemin et les commandes inférieures, les colonnes, la grille, le curseur, les préférences et l’archive. Le contrôle de miniatures exige des représentations autres qu’une simple icône pour PNG, SVG, PDF et vidéo.

Le scénario Quick Look lance le service système par `qlmanage -p` et contrôle les événements de notre extension. Il prouve son invocation et le chargement des enfants, sans constituer une automatisation exhaustive des clics dans Finder. Le bundle a aussi été observé chargé dans Droppy Playground, avec un événement d’activation de `folder-preview-droplet 1.0.0`.

## Limites

Folder Preview d’Anybox n’a pas été exécuté : sa parité complète, ses valeurs non publiées et son code interne ne sont pas certifiés. Les comparaisons reposent sur les captures publiques citées dans `ANALYSE.md`. Les images du dépôt sont des rendus du contrôleur réel de cette réimplémentation, avec des fichiers propres au projet.

Restent à valider manuellement selon les usages : menu contextuel et collage après fermeture, clavier dans Finder, gestionnaires tiers, conflits de fournisseurs, volumes réseau, cloud, accessibilité complète et installation d’une copie téléchargée avec quarantaine. Ces points ne sont pas annoncés comme testés.

Les builds sont personnels, signés ad hoc, sans identité Developer ID ni notarisation. L’extension a été enregistrée et activée sur le Mac de validation. Le chargement d’un droplet local dans Droppy reste soumis à l’autorisation que l’application demande à l’utilisateur.
