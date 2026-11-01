# Dépendances et provenance

- DroppyKit 1.20.1 : dépendance verrouillée, https://gitlab.com/droppyformac1/droppykit. Le droplet lie le framework de Droppy.
- libarchive livré par macOS : les en-têtes de `Native/CArchive` et les petites archives de `Tests/Fixtures` proviennent du tag upstream v3.7.7, https://github.com/libarchive/libarchive/tree/v3.7.7. Les en-têtes conservent les mentions et conditions BSD. Les fixtures servent uniquement aux tests, pas aux documents de démonstration.
- Frameworks Apple système : AppKit, Foundation, Quartz/Quick Look, QuickLookThumbnailing, ImageIO, CoreServices, UniformTypeIdentifiers.
- Démonstrations : fichiers générés pour ce projet. La vidéo a été produite depuis une mire de test FFmpeg ; sa présence n’est pas une dépendance d’exécution de l’extension.
- Icône : composition avec l’icône système de dossier et un symbole SF, sans reprendre l’icône de l’application de référence.

Aucun code ni binaire de Folder Preview/Anybox n’est inclus. L’étude s’appuie sur les documents publics et captures cités dans `ANALYSE.md`. Les sources du droplet portent la licence MIT ; les composants tiers conservent leurs propres conditions.
