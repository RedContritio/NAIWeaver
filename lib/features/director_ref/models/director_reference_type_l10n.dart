import '../../../l10n/app_localizations.dart';
import 'director_reference.dart';

extension DirectorReferenceTypeL10n on DirectorReferenceType {
  String localizedLabel(AppLocalizations l) => switch (this) {
        DirectorReferenceType.character => l.refTypeCharacter,
        DirectorReferenceType.style => l.refTypeStyle,
        DirectorReferenceType.characterAndStyle => l.refTypeCharAndStyle,
      };
}
