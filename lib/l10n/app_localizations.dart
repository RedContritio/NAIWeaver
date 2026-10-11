import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('zh'),
  ];

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get commonHelp;

  /// No description provided for @commonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get commonCreate;

  /// No description provided for @commonRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get commonRename;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonSet.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get commonSet;

  /// No description provided for @commonNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get commonNone;

  /// No description provided for @commonExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get commonExport;

  /// No description provided for @commonOverwrite.
  ///
  /// In en, this message translates to:
  /// **'OVERWRITE'**
  String get commonOverwrite;

  /// No description provided for @commonSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'SAVE CHANGES'**
  String get commonSaveChanges;

  /// No description provided for @commonNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name cannot be empty'**
  String get commonNameRequired;

  /// No description provided for @commonDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get commonDuplicate;

  /// No description provided for @commonDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get commonDiscard;

  /// No description provided for @commonAddFavorite.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get commonAddFavorite;

  /// No description provided for @commonRemoveFavorite.
  ///
  /// In en, this message translates to:
  /// **'Remove from favorites'**
  String get commonRemoveFavorite;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get commonLoading;

  /// No description provided for @commonUnsavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get commonUnsavedTitle;

  /// No description provided for @commonUnsavedMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. Save them before continuing?'**
  String get commonUnsavedMessage;

  /// No description provided for @mainGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get mainGallery;

  /// No description provided for @mainResultsGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get mainResultsGrid;

  /// No description provided for @mainResultsViewer.
  ///
  /// In en, this message translates to:
  /// **'Viewer'**
  String get mainResultsViewer;

  /// No description provided for @mainResultGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating'**
  String get mainResultGenerating;

  /// No description provided for @mainResultPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get mainResultPending;

  /// No description provided for @mainServerHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get mainServerHistory;

  /// No description provided for @mainTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get mainTools;

  /// No description provided for @mainSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get mainSave;

  /// No description provided for @mainExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get mainExport;

  /// No description provided for @mainEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get mainEdit;

  /// No description provided for @mainEnterPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter Prompt'**
  String get mainEnterPrompt;

  /// No description provided for @mainMoreActions.
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get mainMoreActions;

  /// No description provided for @mainHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get mainHelp;

  /// No description provided for @mainAuthError.
  ///
  /// In en, this message translates to:
  /// **'Authentication error: please check API settings'**
  String get mainAuthError;

  /// No description provided for @mainSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get mainSettings;

  /// No description provided for @mainImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to import settings: {error}'**
  String mainImportFailed(String error);

  /// No description provided for @mainSavePreset.
  ///
  /// In en, this message translates to:
  /// **'Save Preset'**
  String get mainSavePreset;

  /// No description provided for @mainPresetName.
  ///
  /// In en, this message translates to:
  /// **'Preset Name'**
  String get mainPresetName;

  /// No description provided for @generationSheetPrompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get generationSheetPrompt;

  /// No description provided for @generationSheetInputs.
  ///
  /// In en, this message translates to:
  /// **'Inputs'**
  String get generationSheetInputs;

  /// No description provided for @generationSheetParameters.
  ///
  /// In en, this message translates to:
  /// **'Parameters'**
  String get generationSheetParameters;

  /// No description provided for @mainExitConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to exit?'**
  String get mainExitConfirmation;

  /// No description provided for @settingsApiSettings.
  ///
  /// In en, this message translates to:
  /// **'API Settings'**
  String get settingsApiSettings;

  /// No description provided for @settingsGeneralSettings.
  ///
  /// In en, this message translates to:
  /// **'General Settings'**
  String get settingsGeneralSettings;

  /// No description provided for @settingsUiSettings.
  ///
  /// In en, this message translates to:
  /// **'UI Settings'**
  String get settingsUiSettings;

  /// No description provided for @settingsExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get settingsExport;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsSecurity;

  /// No description provided for @settingsDemoMode.
  ///
  /// In en, this message translates to:
  /// **'Demo Mode'**
  String get settingsDemoMode;

  /// No description provided for @settingsLinks.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get settingsLinks;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsApiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'NovelAI API Key'**
  String get settingsApiKeyLabel;

  /// No description provided for @settingsApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'pst-xxxx...'**
  String get settingsApiKeyHint;

  /// No description provided for @settingsApiKeyVisibility.
  ///
  /// In en, this message translates to:
  /// **'Show or hide the API key'**
  String get settingsApiKeyVisibility;

  /// No description provided for @settingsApiManaged.
  ///
  /// In en, this message translates to:
  /// **'NovelAI API Key Managed By Server'**
  String get settingsApiManaged;

  /// No description provided for @settingsApiManagedDesc.
  ///
  /// In en, this message translates to:
  /// **'This web service uses the backend NovelAI token. The browser never stores or sends your NovelAI token.'**
  String get settingsApiManagedDesc;

  /// No description provided for @gatewayLogout.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get gatewayLogout;

  /// No description provided for @gatewayQueueStatus.
  ///
  /// In en, this message translates to:
  /// **'Queue status'**
  String get gatewayQueueStatus;

  /// No description provided for @gatewayQueueIdle.
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get gatewayQueueIdle;

  /// No description provided for @gatewayQueueQueued.
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get gatewayQueueQueued;

  /// No description provided for @gatewayQueueActive.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get gatewayQueueActive;

  /// No description provided for @gatewayQuotaFreeLabel.
  ///
  /// In en, this message translates to:
  /// **'Free quota'**
  String get gatewayQuotaFreeLabel;

  /// No description provided for @gatewayQuotaPaidLabel.
  ///
  /// In en, this message translates to:
  /// **'Paid points'**
  String get gatewayQuotaPaidLabel;

  /// No description provided for @gatewayQuotaUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get gatewayQuotaUnlimited;

  /// No description provided for @gatewayQuotaRefresh.
  ///
  /// In en, this message translates to:
  /// **'Tap to refresh your quota'**
  String get gatewayQuotaRefresh;

  /// No description provided for @gatewayErrNotAuthenticated.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Sign in again.'**
  String get gatewayErrNotAuthenticated;

  /// No description provided for @gatewayErrAuthUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The sign-in service is temporarily unavailable. Try again later.'**
  String get gatewayErrAuthUnavailable;

  /// No description provided for @gatewayErrLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign-in could not be verified. Try again.'**
  String get gatewayErrLoginFailed;

  /// No description provided for @gatewayErrAccountNotLinked.
  ///
  /// In en, this message translates to:
  /// **'This sign-in is not linked to an account here, or the account is disabled.'**
  String get gatewayErrAccountNotLinked;

  /// No description provided for @gatewayErrPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Your account is not allowed to do this.'**
  String get gatewayErrPermissionDenied;

  /// No description provided for @gatewayErrInvalidParameters.
  ///
  /// In en, this message translates to:
  /// **'The request was rejected as invalid. Check the size, steps and sampler.'**
  String get gatewayErrInvalidParameters;

  /// No description provided for @gatewayErrPointsInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Not enough points for this request.'**
  String get gatewayErrPointsInsufficient;

  /// No description provided for @gatewayErrQuoteChanged.
  ///
  /// In en, this message translates to:
  /// **'The price has changed. Review the new price and try again.'**
  String get gatewayErrQuoteChanged;

  /// No description provided for @gatewayErrFreeAllowanceExhausted.
  ///
  /// In en, this message translates to:
  /// **'The free allowance is used up for now, so this request would cost paid points.'**
  String get gatewayErrFreeAllowanceExhausted;

  /// No description provided for @gatewayErrQueueFull.
  ///
  /// In en, this message translates to:
  /// **'You have too many unfinished tasks. Wait for some to finish before submitting more.'**
  String get gatewayErrQueueFull;

  /// No description provided for @gatewayErrDuplicateRequest.
  ///
  /// In en, this message translates to:
  /// **'This request id was already used with different content.'**
  String get gatewayErrDuplicateRequest;

  /// No description provided for @gatewayErrRequestTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The request is too large.'**
  String get gatewayErrRequestTooLarge;

  /// No description provided for @gatewayErrUpstream.
  ///
  /// In en, this message translates to:
  /// **'NovelAI could not complete the request. Try again later.'**
  String get gatewayErrUpstream;

  /// No description provided for @gatewayErrInterrupted.
  ///
  /// In en, this message translates to:
  /// **'The task was interrupted by a server restart. You were not charged; you can retry.'**
  String get gatewayErrInterrupted;

  /// No description provided for @gatewayErrNotFound.
  ///
  /// In en, this message translates to:
  /// **'The requested item was not found.'**
  String get gatewayErrNotFound;

  /// No description provided for @gatewayErrTaskActive.
  ///
  /// In en, this message translates to:
  /// **'This item is still queued or running.'**
  String get gatewayErrTaskActive;

  /// No description provided for @gatewayErrDuplicateGeneration.
  ///
  /// In en, this message translates to:
  /// **'The parameters did not change. Check the seed.'**
  String get gatewayErrDuplicateGeneration;

  /// No description provided for @gatewayErrRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Wait a moment and try again.'**
  String get gatewayErrRateLimited;

  /// No description provided for @gatewayErrServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The service is temporarily unavailable. Try again later.'**
  String get gatewayErrServiceUnavailable;

  /// No description provided for @gatewayErrInternal.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong on the server. Try again later.'**
  String get gatewayErrInternal;

  /// No description provided for @gatewayErrNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error. Check your connection and try again.'**
  String get gatewayErrNetwork;

  /// No description provided for @gatewayErrTimeout.
  ///
  /// In en, this message translates to:
  /// **'The request timed out. Try again.'**
  String get gatewayErrTimeout;

  /// No description provided for @gatewayErrUnknown.
  ///
  /// In en, this message translates to:
  /// **'The request failed. Try again later.'**
  String get gatewayErrUnknown;

  /// No description provided for @gatewayErrDirectAnlas.
  ///
  /// In en, this message translates to:
  /// **'Your NovelAI account does not have enough Anlas for this request.'**
  String get gatewayErrDirectAnlas;

  /// No description provided for @gatewayErrDirectRateLimited.
  ///
  /// In en, this message translates to:
  /// **'NovelAI is limiting your requests. Wait a moment and try again.'**
  String get gatewayErrDirectRateLimited;

  /// No description provided for @gatewayErrDirectForbidden.
  ///
  /// In en, this message translates to:
  /// **'NovelAI refused this request for your account.'**
  String get gatewayErrDirectForbidden;

  /// No description provided for @toolErrApiKeyRejected.
  ///
  /// In en, this message translates to:
  /// **'NovelAI rejected the API key. Check it in Settings.'**
  String get toolErrApiKeyRejected;

  /// No description provided for @gatewaySessionExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Session expired'**
  String get gatewaySessionExpiredTitle;

  /// No description provided for @gatewaySessionExpiredBody.
  ///
  /// In en, this message translates to:
  /// **'Your sign-in has ended. Sign in again to continue; nothing on this page is lost until you do.'**
  String get gatewaySessionExpiredBody;

  /// No description provided for @gatewaySessionExpiredConfirm.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get gatewaySessionExpiredConfirm;

  /// No description provided for @gatewayAuthContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue with only WebAuth'**
  String get gatewayAuthContinue;

  /// No description provided for @gatewayAuthRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get gatewayAuthRetry;

  /// No description provided for @gatewayLoginOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the sign-in page. Reload and try again.'**
  String get gatewayLoginOpenFailed;

  /// No description provided for @gatewayLogoutFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not sign out. You are still signed in; try again.'**
  String get gatewayLogoutFailed;

  /// No description provided for @settingsAutoSave.
  ///
  /// In en, this message translates to:
  /// **'Auto-Save Images'**
  String get settingsAutoSave;

  /// No description provided for @settingsAutoSaveDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically save all generated images to the output folder'**
  String get settingsAutoSaveDesc;

  /// No description provided for @settingsSmartStyleImport.
  ///
  /// In en, this message translates to:
  /// **'Smart Style Import'**
  String get settingsSmartStyleImport;

  /// No description provided for @settingsSmartStyleImportDesc.
  ///
  /// In en, this message translates to:
  /// **'Strip style tags from imported prompts and restore style selections instead'**
  String get settingsSmartStyleImportDesc;

  /// No description provided for @settingsCharInsertTarget.
  ///
  /// In en, this message translates to:
  /// **'Add Saved Characters To Editor'**
  String get settingsCharInsertTarget;

  /// No description provided for @settingsCharInsertTargetDesc.
  ///
  /// In en, this message translates to:
  /// **'Picking a saved character from the prompt box adds a character card instead of inserting its tags into the main prompt'**
  String get settingsCharInsertTargetDesc;

  /// No description provided for @settingsRememberSession.
  ///
  /// In en, this message translates to:
  /// **'Remember Session'**
  String get settingsRememberSession;

  /// No description provided for @settingsRememberSessionDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-save your prompt, settings, and references for crash recovery'**
  String get settingsRememberSessionDesc;

  /// No description provided for @settingsImg2ImgImportPrompt.
  ///
  /// In en, this message translates to:
  /// **'Img2Img Import Prompt'**
  String get settingsImg2ImgImportPrompt;

  /// No description provided for @settingsImg2ImgImportPromptDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-fill img2img prompt when selecting a source image with metadata'**
  String get settingsImg2ImgImportPromptDesc;

  /// No description provided for @settingsSaveToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Save to Album'**
  String get settingsSaveToAlbum;

  /// No description provided for @settingsSaveToAlbumDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-add new generations to this album'**
  String get settingsSaveToAlbumDesc;

  /// No description provided for @settingsEditButton.
  ///
  /// In en, this message translates to:
  /// **'Edit Button'**
  String get settingsEditButton;

  /// No description provided for @settingsEditButtonDesc.
  ///
  /// In en, this message translates to:
  /// **'Show the edit/inpainting button on the image viewer'**
  String get settingsEditButtonDesc;

  /// No description provided for @settingsDirectorRefShelf.
  ///
  /// In en, this message translates to:
  /// **'Director References'**
  String get settingsDirectorRefShelf;

  /// No description provided for @settingsDirectorRefShelfDesc.
  ///
  /// In en, this message translates to:
  /// **'Show director reference controls in advanced options'**
  String get settingsDirectorRefShelfDesc;

  /// No description provided for @settingsVibeTransferShelf.
  ///
  /// In en, this message translates to:
  /// **'Vibe Transfer'**
  String get settingsVibeTransferShelf;

  /// No description provided for @settingsVibeTransferShelfDesc.
  ///
  /// In en, this message translates to:
  /// **'Show vibe transfer controls in advanced options'**
  String get settingsVibeTransferShelfDesc;

  /// No description provided for @settingsCharEditorMode.
  ///
  /// In en, this message translates to:
  /// **'Character Editor Mode'**
  String get settingsCharEditorMode;

  /// No description provided for @settingsCharEditorModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the expanded character editor in the settings panel instead of the compact shelf'**
  String get settingsCharEditorModeDesc;

  /// No description provided for @settingsThemeBuilder.
  ///
  /// In en, this message translates to:
  /// **'Theme Builder'**
  String get settingsThemeBuilder;

  /// No description provided for @settingsStripMetadata.
  ///
  /// In en, this message translates to:
  /// **'Strip Metadata on Export'**
  String get settingsStripMetadata;

  /// No description provided for @settingsStripMetadataDesc.
  ///
  /// In en, this message translates to:
  /// **'Remove generation data (prompt, settings) from exported images'**
  String get settingsStripMetadataDesc;

  /// No description provided for @settingsPinLock.
  ///
  /// In en, this message translates to:
  /// **'PIN Lock'**
  String get settingsPinLock;

  /// No description provided for @settingsPinLockDesc.
  ///
  /// In en, this message translates to:
  /// **'Require a PIN (4-8 digits) to open the app'**
  String get settingsPinLockDesc;

  /// No description provided for @settingsLockOnResume.
  ///
  /// In en, this message translates to:
  /// **'Lock on Resume'**
  String get settingsLockOnResume;

  /// No description provided for @settingsLockOnResumeDesc.
  ///
  /// In en, this message translates to:
  /// **'Re-lock app when returning from background'**
  String get settingsLockOnResumeDesc;

  /// No description provided for @settingsBiometricUnlock.
  ///
  /// In en, this message translates to:
  /// **'Biometric Unlock'**
  String get settingsBiometricUnlock;

  /// No description provided for @settingsBiometricUnlockDesc.
  ///
  /// In en, this message translates to:
  /// **'Use fingerprint or face unlock'**
  String get settingsBiometricUnlockDesc;

  /// No description provided for @settingsBiometricsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Biometrics not available on this device'**
  String get settingsBiometricsUnavailable;

  /// No description provided for @settingsSetPin.
  ///
  /// In en, this message translates to:
  /// **'Set PIN'**
  String get settingsSetPin;

  /// No description provided for @settingsPinDigitsHint.
  ///
  /// In en, this message translates to:
  /// **'4-8 digits'**
  String get settingsPinDigitsHint;

  /// No description provided for @settingsPinMustBeDigits.
  ///
  /// In en, this message translates to:
  /// **'PIN must be 4-8 digits'**
  String get settingsPinMustBeDigits;

  /// No description provided for @settingsPinsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'PINs do not match'**
  String get settingsPinsDoNotMatch;

  /// No description provided for @settingsEnterCurrentPin.
  ///
  /// In en, this message translates to:
  /// **'Enter Current PIN'**
  String get settingsEnterCurrentPin;

  /// No description provided for @settingsEnterPinHint.
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get settingsEnterPinHint;

  /// No description provided for @settingsIncorrectPin.
  ///
  /// In en, this message translates to:
  /// **'Incorrect PIN'**
  String get settingsIncorrectPin;

  /// No description provided for @settingsDemoModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Only show demo-safe images in the gallery'**
  String get settingsDemoModeDesc;

  /// No description provided for @settingsSelectDemoImages.
  ///
  /// In en, this message translates to:
  /// **'Select Demo Images'**
  String get settingsSelectDemoImages;

  /// No description provided for @settingsTagSuggestionsHidden.
  ///
  /// In en, this message translates to:
  /// **'Tag suggestions are hidden while demo mode is active'**
  String get settingsTagSuggestionsHidden;

  /// No description provided for @settingsPositivePrefix.
  ///
  /// In en, this message translates to:
  /// **'Positive Prefix'**
  String get settingsPositivePrefix;

  /// No description provided for @settingsNegativePrefix.
  ///
  /// In en, this message translates to:
  /// **'Negative Prefix'**
  String get settingsNegativePrefix;

  /// No description provided for @settingsEditPositivePrefix.
  ///
  /// In en, this message translates to:
  /// **'Edit Positive Prefix'**
  String get settingsEditPositivePrefix;

  /// No description provided for @settingsDemoPrefixes.
  ///
  /// In en, this message translates to:
  /// **'Demo Prefixes'**
  String get settingsDemoPrefixes;

  /// No description provided for @settingsGithubRepository.
  ///
  /// In en, this message translates to:
  /// **'GitHub Repository'**
  String get settingsGithubRepository;

  /// No description provided for @galleryTitle.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get galleryTitle;

  /// No description provided for @galleryDemoTitle.
  ///
  /// In en, this message translates to:
  /// **'Gallery (Demo)'**
  String get galleryDemoTitle;

  /// No description provided for @gallerySearchTags.
  ///
  /// In en, this message translates to:
  /// **'Search Tags...'**
  String get gallerySearchTags;

  /// No description provided for @gallerySelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Selected'**
  String gallerySelectedCount(int count);

  /// No description provided for @galleryDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get galleryDeselectAll;

  /// No description provided for @gallerySelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get gallerySelectAll;

  /// No description provided for @galleryFavoritesFilter.
  ///
  /// In en, this message translates to:
  /// **'Favorites filter'**
  String get galleryFavoritesFilter;

  /// No description provided for @gallerySort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get gallerySort;

  /// No description provided for @gallerySelectMode.
  ///
  /// In en, this message translates to:
  /// **'Select mode'**
  String get gallerySelectMode;

  /// No description provided for @galleryColumnsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} columns'**
  String galleryColumnsCount(int count);

  /// No description provided for @gallerySortDateNewest.
  ///
  /// In en, this message translates to:
  /// **'Date (Newest)'**
  String get gallerySortDateNewest;

  /// No description provided for @gallerySortDateOldest.
  ///
  /// In en, this message translates to:
  /// **'Date (Oldest)'**
  String get gallerySortDateOldest;

  /// No description provided for @gallerySortNameAZ.
  ///
  /// In en, this message translates to:
  /// **'Name (A-Z)'**
  String get gallerySortNameAZ;

  /// No description provided for @gallerySortNameZA.
  ///
  /// In en, this message translates to:
  /// **'Name (Z-A)'**
  String get gallerySortNameZA;

  /// No description provided for @gallerySortSizeLargest.
  ///
  /// In en, this message translates to:
  /// **'Size (Largest)'**
  String get gallerySortSizeLargest;

  /// No description provided for @gallerySortSizeSmallest.
  ///
  /// In en, this message translates to:
  /// **'Size (Smallest)'**
  String get gallerySortSizeSmallest;

  /// No description provided for @gallerySortDateAddedNewest.
  ///
  /// In en, this message translates to:
  /// **'Date Added (Newest)'**
  String get gallerySortDateAddedNewest;

  /// No description provided for @gallerySortDateAddedOldest.
  ///
  /// In en, this message translates to:
  /// **'Date Added (Oldest)'**
  String get gallerySortDateAddedOldest;

  /// No description provided for @galleryNoDemoImages.
  ///
  /// In en, this message translates to:
  /// **'No demo images selected'**
  String get galleryNoDemoImages;

  /// No description provided for @galleryNoFavorites.
  ///
  /// In en, this message translates to:
  /// **'No Favorites'**
  String get galleryNoFavorites;

  /// No description provided for @galleryNoImagesInAlbum.
  ///
  /// In en, this message translates to:
  /// **'No Images in Album'**
  String get galleryNoImagesInAlbum;

  /// No description provided for @galleryNoImagesFound.
  ///
  /// In en, this message translates to:
  /// **'No Images Found'**
  String get galleryNoImagesFound;

  /// No description provided for @galleryAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get galleryAll;

  /// No description provided for @galleryCopiedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Copied'**
  String galleryCopiedCount(int count);

  /// No description provided for @galleryImagesCopiedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Images Copied'**
  String galleryImagesCopiedCount(int count);

  /// No description provided for @galleryPasteInto.
  ///
  /// In en, this message translates to:
  /// **'Paste Into {name}'**
  String galleryPasteInto(String name);

  /// No description provided for @galleryPastedIntoAlbum.
  ///
  /// In en, this message translates to:
  /// **'{count} images pasted into {name}'**
  String galleryPastedIntoAlbum(int count, String name);

  /// No description provided for @galleryClearClipboard.
  ///
  /// In en, this message translates to:
  /// **'Clear Clipboard'**
  String get galleryClearClipboard;

  /// No description provided for @galleryNewAlbum.
  ///
  /// In en, this message translates to:
  /// **'New Album'**
  String get galleryNewAlbum;

  /// No description provided for @galleryAlbumName.
  ///
  /// In en, this message translates to:
  /// **'Album Name'**
  String get galleryAlbumName;

  /// No description provided for @galleryRenameAlbum.
  ///
  /// In en, this message translates to:
  /// **'Rename Album'**
  String get galleryRenameAlbum;

  /// No description provided for @galleryAddToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Add to Album'**
  String get galleryAddToAlbum;

  /// No description provided for @galleryAddedToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Added to {name}'**
  String galleryAddedToAlbum(String name);

  /// No description provided for @galleryMoveToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Move to Album'**
  String get galleryMoveToAlbum;

  /// No description provided for @galleryMove.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get galleryMove;

  /// No description provided for @galleryDeleteAlbumTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete album \"{name}\"?'**
  String galleryDeleteAlbumTitle(String name);

  /// No description provided for @galleryDeleteAlbumMessage.
  ///
  /// In en, this message translates to:
  /// **'The images stay in the gallery.'**
  String get galleryDeleteAlbumMessage;

  /// No description provided for @galleryRemoveFromAlbum.
  ///
  /// In en, this message translates to:
  /// **'Remove from album'**
  String get galleryRemoveFromAlbum;

  /// No description provided for @galleryRemoveFromAlbumTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove from album?'**
  String get galleryRemoveFromAlbumTitle;

  /// No description provided for @galleryRemoveFromAlbumCount.
  ///
  /// In en, this message translates to:
  /// **'Remove {count} images from this album?'**
  String galleryRemoveFromAlbumCount(int count);

  /// No description provided for @galleryRemoveFromAlbumMessage.
  ///
  /// In en, this message translates to:
  /// **'The images stay in the gallery.'**
  String get galleryRemoveFromAlbumMessage;

  /// No description provided for @galleryRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get galleryRemove;

  /// No description provided for @galleryDeleteCount.
  ///
  /// In en, this message translates to:
  /// **'Delete {count} images?'**
  String galleryDeleteCount(int count);

  /// No description provided for @galleryCannotUndo.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get galleryCannotUndo;

  /// No description provided for @galleryCompare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get galleryCompare;

  /// No description provided for @galleryCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get galleryCopy;

  /// No description provided for @galleryShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get galleryShare;

  /// No description provided for @galleryPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get galleryPaste;

  /// No description provided for @galleryAlbum.
  ///
  /// In en, this message translates to:
  /// **'Album'**
  String get galleryAlbum;

  /// No description provided for @galleryFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get galleryFavorite;

  /// No description provided for @gallerySavedToDeviceCount.
  ///
  /// In en, this message translates to:
  /// **'Saved {saved}/{total} to device gallery'**
  String gallerySavedToDeviceCount(int saved, int total);

  /// No description provided for @galleryExportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Export {count} Images'**
  String galleryExportDialogTitle(int count);

  /// No description provided for @galleryExportedToFolder.
  ///
  /// In en, this message translates to:
  /// **'Exported {count} images to {folder}'**
  String galleryExportedToFolder(int count, String folder);

  /// No description provided for @galleryExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String galleryExportFailed(String error);

  /// No description provided for @galleryExportFolderUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Export folder unavailable. Pick it again in Settings.'**
  String get galleryExportFolderUnavailable;

  /// No description provided for @galleryImagesCopied.
  ///
  /// In en, this message translates to:
  /// **'{count} images copied'**
  String galleryImagesCopied(int count);

  /// No description provided for @galleryImagesPasted.
  ///
  /// In en, this message translates to:
  /// **'{count} images pasted'**
  String galleryImagesPasted(int count);

  /// No description provided for @galleryDeleteImage.
  ///
  /// In en, this message translates to:
  /// **'Delete Image?'**
  String get galleryDeleteImage;

  /// No description provided for @gallerySavedToDevice.
  ///
  /// In en, this message translates to:
  /// **'Saved to device gallery'**
  String get gallerySavedToDevice;

  /// No description provided for @galleryExportImageDialog.
  ///
  /// In en, this message translates to:
  /// **'Export Image'**
  String get galleryExportImageDialog;

  /// No description provided for @gallerySavedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved to {name}'**
  String gallerySavedTo(String name);

  /// No description provided for @galleryResultDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded {name}'**
  String galleryResultDownloaded(String name);

  /// No description provided for @galleryResultSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Result not saved: {error}'**
  String galleryResultSaveFailed(String error);

  /// No description provided for @galleryNewImageHidden.
  ///
  /// In en, this message translates to:
  /// **'New image saved, but the current filter hides it'**
  String get galleryNewImageHidden;

  /// No description provided for @galleryToggleFavorite.
  ///
  /// In en, this message translates to:
  /// **'Toggle favorite'**
  String get galleryToggleFavorite;

  /// No description provided for @galleryExportImage.
  ///
  /// In en, this message translates to:
  /// **'Export image'**
  String get galleryExportImage;

  /// No description provided for @galleryDeleteImageTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete image'**
  String get galleryDeleteImageTooltip;

  /// No description provided for @galleryNoPrompt.
  ///
  /// In en, this message translates to:
  /// **'No Prompt'**
  String get galleryNoPrompt;

  /// No description provided for @galleryNoMetadata.
  ///
  /// In en, this message translates to:
  /// **'No Metadata'**
  String get galleryNoMetadata;

  /// No description provided for @galleryCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get galleryCopiedToClipboard;

  /// No description provided for @galleryClipboardUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Clipboard not available'**
  String get galleryClipboardUnavailable;

  /// No description provided for @galleryPrompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get galleryPrompt;

  /// No description provided for @galleryImg2img.
  ///
  /// In en, this message translates to:
  /// **'IMG2IMG'**
  String get galleryImg2img;

  /// No description provided for @galleryCharRef.
  ///
  /// In en, this message translates to:
  /// **'Char Ref'**
  String get galleryCharRef;

  /// No description provided for @galleryVibe.
  ///
  /// In en, this message translates to:
  /// **'Vibe'**
  String get galleryVibe;

  /// No description provided for @gallerySlideshow.
  ///
  /// In en, this message translates to:
  /// **'Slideshow'**
  String get gallerySlideshow;

  /// No description provided for @galleryAddedAsCharRef.
  ///
  /// In en, this message translates to:
  /// **'Added as character reference'**
  String get galleryAddedAsCharRef;

  /// No description provided for @galleryAddedAsVibe.
  ///
  /// In en, this message translates to:
  /// **'Added as vibe transfer'**
  String get galleryAddedAsVibe;

  /// No description provided for @galleryVibeTransferFailed.
  ///
  /// In en, this message translates to:
  /// **'Vibe transfer failed: {error}'**
  String galleryVibeTransferFailed(String error);

  /// No description provided for @galleryScale.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get galleryScale;

  /// No description provided for @gallerySteps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get gallerySteps;

  /// No description provided for @gallerySampler.
  ///
  /// In en, this message translates to:
  /// **'Sampler'**
  String get gallerySampler;

  /// No description provided for @gallerySeed.
  ///
  /// In en, this message translates to:
  /// **'Seed'**
  String get gallerySeed;

  /// No description provided for @galleryResolution.
  ///
  /// In en, this message translates to:
  /// **'Res'**
  String get galleryResolution;

  /// No description provided for @galleryEnhance.
  ///
  /// In en, this message translates to:
  /// **'Enhance'**
  String get galleryEnhance;

  /// No description provided for @galleryDirectorTools.
  ///
  /// In en, this message translates to:
  /// **'Director'**
  String get galleryDirectorTools;

  /// No description provided for @galleryImport.
  ///
  /// In en, this message translates to:
  /// **'Import Images'**
  String get galleryImport;

  /// No description provided for @galleryImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get galleryImporting;

  /// No description provided for @galleryImportProgress.
  ///
  /// In en, this message translates to:
  /// **'Importing {current}/{total}...'**
  String galleryImportProgress(int current, int total);

  /// No description provided for @galleryImportPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing...'**
  String get galleryImportPreparing;

  /// No description provided for @galleryImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} images ({metadata} with NovelAI metadata)'**
  String galleryImportSuccess(int count, int metadata);

  /// No description provided for @galleryImportConverted.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} images ({converted} converted to PNG)'**
  String galleryImportConverted(int count, int converted);

  /// No description provided for @galleryImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String galleryImportFailed(String error);

  /// No description provided for @galleryImportToEditor.
  ///
  /// In en, this message translates to:
  /// **'Import to editor'**
  String get galleryImportToEditor;

  /// No description provided for @galleryMetadataImported.
  ///
  /// In en, this message translates to:
  /// **'Metadata imported to editor'**
  String get galleryMetadataImported;

  /// No description provided for @galleryMetadataNotFound.
  ///
  /// In en, this message translates to:
  /// **'No metadata found'**
  String get galleryMetadataNotFound;

  /// No description provided for @panelAdvancedSettings.
  ///
  /// In en, this message translates to:
  /// **'Advanced Settings'**
  String get panelAdvancedSettings;

  /// No description provided for @panelDimensions.
  ///
  /// In en, this message translates to:
  /// **'Dimensions'**
  String get panelDimensions;

  /// No description provided for @panelSeed.
  ///
  /// In en, this message translates to:
  /// **'Seed'**
  String get panelSeed;

  /// No description provided for @panelBatchCount.
  ///
  /// In en, this message translates to:
  /// **'Batch'**
  String get panelBatchCount;

  /// No description provided for @panelCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get panelCustom;

  /// No description provided for @panelSteps.
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get panelSteps;

  /// No description provided for @panelScale.
  ///
  /// In en, this message translates to:
  /// **'Scale'**
  String get panelScale;

  /// No description provided for @panelSampler.
  ///
  /// In en, this message translates to:
  /// **'Sampler'**
  String get panelSampler;

  /// No description provided for @panelStyles.
  ///
  /// In en, this message translates to:
  /// **'Styles'**
  String get panelStyles;

  /// No description provided for @panelManageStyles.
  ///
  /// In en, this message translates to:
  /// **'Manage Styles'**
  String get panelManageStyles;

  /// No description provided for @panelEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get panelEnabled;

  /// No description provided for @panelNoStylesDefined.
  ///
  /// In en, this message translates to:
  /// **'No Styles Defined'**
  String get panelNoStylesDefined;

  /// No description provided for @panelNegativePrompt.
  ///
  /// In en, this message translates to:
  /// **'Negative Prompt'**
  String get panelNegativePrompt;

  /// No description provided for @panelPresets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get panelPresets;

  /// No description provided for @panelNoPresetsSaved.
  ///
  /// In en, this message translates to:
  /// **'No Presets Saved'**
  String get panelNoPresetsSaved;

  /// No description provided for @panelDeletePreset.
  ///
  /// In en, this message translates to:
  /// **'Delete Preset'**
  String get panelDeletePreset;

  /// No description provided for @panelDeletePresetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String panelDeletePresetConfirm(String name);

  /// No description provided for @panelDeleteResolution.
  ///
  /// In en, this message translates to:
  /// **'Delete Custom Resolution'**
  String get panelDeleteResolution;

  /// No description provided for @panelDeleteResolutionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete the custom resolution \"{name}\"?'**
  String panelDeleteResolutionConfirm(String name);

  /// No description provided for @panelInputsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No reference inputs'**
  String get panelInputsEmptyTitle;

  /// No description provided for @panelInputsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Precise references and vibe transfer are paid tools that this account cannot use, and none have been added.'**
  String get panelInputsEmptyMessage;

  /// No description provided for @panelInputsHiddenMessage.
  ///
  /// In en, this message translates to:
  /// **'The precise reference and vibe transfer shelves are turned off in Settings.'**
  String get panelInputsHiddenMessage;

  /// No description provided for @panelSaveToAlbum.
  ///
  /// In en, this message translates to:
  /// **'Save to Album'**
  String get panelSaveToAlbum;

  /// No description provided for @panelNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get panelNew;

  /// No description provided for @panelNewAlbum.
  ///
  /// In en, this message translates to:
  /// **'New Album'**
  String get panelNewAlbum;

  /// No description provided for @panelAlbumName.
  ///
  /// In en, this message translates to:
  /// **'Album Name'**
  String get panelAlbumName;

  /// No description provided for @resNormalPortrait.
  ///
  /// In en, this message translates to:
  /// **'Normal Portrait'**
  String get resNormalPortrait;

  /// No description provided for @resNormalLandscape.
  ///
  /// In en, this message translates to:
  /// **'Normal Landscape'**
  String get resNormalLandscape;

  /// No description provided for @resNormalSquare.
  ///
  /// In en, this message translates to:
  /// **'Normal Square'**
  String get resNormalSquare;

  /// No description provided for @resLargePortrait.
  ///
  /// In en, this message translates to:
  /// **'Large Portrait'**
  String get resLargePortrait;

  /// No description provided for @resLargeLandscape.
  ///
  /// In en, this message translates to:
  /// **'Large Landscape'**
  String get resLargeLandscape;

  /// No description provided for @resLargeSquare.
  ///
  /// In en, this message translates to:
  /// **'Large Square'**
  String get resLargeSquare;

  /// No description provided for @resWallpaperPortrait.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper Portrait'**
  String get resWallpaperPortrait;

  /// No description provided for @resWallpaperLandscape.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper Landscape'**
  String get resWallpaperLandscape;

  /// No description provided for @toolsHub.
  ///
  /// In en, this message translates to:
  /// **'Tools Hub'**
  String get toolsHub;

  /// No description provided for @toolsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get toolsTitle;

  /// No description provided for @toolsWildcards.
  ///
  /// In en, this message translates to:
  /// **'Wildcards'**
  String get toolsWildcards;

  /// No description provided for @toolsTagLibrary.
  ///
  /// In en, this message translates to:
  /// **'Tag Library'**
  String get toolsTagLibrary;

  /// No description provided for @toolsPresets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get toolsPresets;

  /// No description provided for @toolsStyles.
  ///
  /// In en, this message translates to:
  /// **'Styles'**
  String get toolsStyles;

  /// No description provided for @toolsReferences.
  ///
  /// In en, this message translates to:
  /// **'References'**
  String get toolsReferences;

  /// No description provided for @toolsCascadeEditor.
  ///
  /// In en, this message translates to:
  /// **'Cascade Editor'**
  String get toolsCascadeEditor;

  /// No description provided for @toolsImg2imgEditor.
  ///
  /// In en, this message translates to:
  /// **'IMG2IMG Editor'**
  String get toolsImg2imgEditor;

  /// No description provided for @toolsSlideshow.
  ///
  /// In en, this message translates to:
  /// **'Slideshow'**
  String get toolsSlideshow;

  /// No description provided for @toolsPacks.
  ///
  /// In en, this message translates to:
  /// **'Packs'**
  String get toolsPacks;

  /// No description provided for @toolsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get toolsTheme;

  /// No description provided for @toolsSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get toolsSettings;

  /// No description provided for @toolsFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get toolsFeedback;

  /// No description provided for @feedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic Feedback'**
  String get feedbackTitle;

  /// No description provided for @feedbackIntro.
  ///
  /// In en, this message translates to:
  /// **'A background diagnostic session continuously retains recent focus, keyboard, viewport, interaction, performance, network, and panel lifecycle events, then attaches them when you submit.'**
  String get feedbackIntro;

  /// No description provided for @feedbackPrivacy.
  ///
  /// In en, this message translates to:
  /// **'The diagnostic log does not include prompt or negative-prompt contents, seeds, images, authentication data, or generation request bodies. It remains in this page\'s memory and is uploaded only when you press Submit.'**
  String get feedbackPrivacy;

  /// No description provided for @feedbackDebugStatus.
  ///
  /// In en, this message translates to:
  /// **'Background diagnostics active · {count} events · {minutes} min covered · {dropped} dropped'**
  String feedbackDebugStatus(int count, int minutes, int dropped);

  /// No description provided for @feedbackDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'What happened? (optional)'**
  String get feedbackDescriptionLabel;

  /// No description provided for @feedbackDescriptionHint.
  ///
  /// In en, this message translates to:
  /// **'For example: I tapped Negative Prompt and the keyboard closed immediately.'**
  String get feedbackDescriptionHint;

  /// No description provided for @feedbackSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit Diagnostic Report'**
  String get feedbackSubmit;

  /// No description provided for @feedbackSubmitting.
  ///
  /// In en, this message translates to:
  /// **'Submitting…'**
  String get feedbackSubmitting;

  /// No description provided for @feedbackSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Report submitted'**
  String get feedbackSubmitted;

  /// No description provided for @feedbackTicketLabel.
  ///
  /// In en, this message translates to:
  /// **'Ticket'**
  String get feedbackTicketLabel;

  /// No description provided for @feedbackCopyTicket.
  ///
  /// In en, this message translates to:
  /// **'Copy ticket ID'**
  String get feedbackCopyTicket;

  /// No description provided for @feedbackTicketCopied.
  ///
  /// In en, this message translates to:
  /// **'Ticket ID copied'**
  String get feedbackTicketCopied;

  /// No description provided for @feedbackSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Submission failed'**
  String get feedbackSubmitFailed;

  /// No description provided for @feedbackUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic reports are available in the authenticated Web app.'**
  String get feedbackUnavailable;

  /// No description provided for @feedbackInvalid.
  ///
  /// In en, this message translates to:
  /// **'The report was rejected. Shorten the description and try again.'**
  String get feedbackInvalid;

  /// No description provided for @helpTitle.
  ///
  /// In en, this message translates to:
  /// **'NAIWeaver'**
  String get helpTitle;

  /// No description provided for @helpShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get helpShortcuts;

  /// No description provided for @helpFeatures.
  ///
  /// In en, this message translates to:
  /// **'Features'**
  String get helpFeatures;

  /// No description provided for @helpShortcutWildcard.
  ///
  /// In en, this message translates to:
  /// **'Random line from wildcards/name.txt'**
  String get helpShortcutWildcard;

  /// No description provided for @helpShortcutWildcardBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse wildcard file to insert'**
  String get helpShortcutWildcardBrowse;

  /// No description provided for @helpShortcutHoldDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss tag suggestion'**
  String get helpShortcutHoldDismiss;

  /// No description provided for @helpShortcutFavorites.
  ///
  /// In en, this message translates to:
  /// **'Show all favorite tags'**
  String get helpShortcutFavorites;

  /// No description provided for @helpShortcutFavCategories.
  ///
  /// In en, this message translates to:
  /// **'Favorites by category'**
  String get helpShortcutFavCategories;

  /// No description provided for @helpShortcutArtistPrefix.
  ///
  /// In en, this message translates to:
  /// **'Filter tag suggestions to artists'**
  String get helpShortcutArtistPrefix;

  /// No description provided for @helpShortcutEnter.
  ///
  /// In en, this message translates to:
  /// **'Generate (or select tag suggestion)'**
  String get helpShortcutEnter;

  /// No description provided for @helpShortcutDragDrop.
  ///
  /// In en, this message translates to:
  /// **'Import generation settings'**
  String get helpShortcutDragDrop;

  /// No description provided for @helpFeatureGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get helpFeatureGallery;

  /// No description provided for @helpFeatureGalleryDesc.
  ///
  /// In en, this message translates to:
  /// **'Browse, favorite, compare, and album-sort outputs'**
  String get helpFeatureGalleryDesc;

  /// No description provided for @helpFeatureWildcards.
  ///
  /// In en, this message translates to:
  /// **'Wildcards'**
  String get helpFeatureWildcards;

  /// No description provided for @helpFeatureWildcardsDesc.
  ///
  /// In en, this message translates to:
  /// **'__pattern__ random substitution from text files'**
  String get helpFeatureWildcardsDesc;

  /// No description provided for @helpFeatureStyles.
  ///
  /// In en, this message translates to:
  /// **'Styles'**
  String get helpFeatureStyles;

  /// No description provided for @helpFeatureStylesDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-inject prefix/suffix/negative into prompts'**
  String get helpFeatureStylesDesc;

  /// No description provided for @helpFeaturePresets.
  ///
  /// In en, this message translates to:
  /// **'Presets'**
  String get helpFeaturePresets;

  /// No description provided for @helpFeaturePresetsDesc.
  ///
  /// In en, this message translates to:
  /// **'Save & restore full generation configurations'**
  String get helpFeaturePresetsDesc;

  /// No description provided for @helpFeatureDirectorRef.
  ///
  /// In en, this message translates to:
  /// **'Director Reference'**
  String get helpFeatureDirectorRef;

  /// No description provided for @helpFeatureDirectorRefDesc.
  ///
  /// In en, this message translates to:
  /// **'Guide character/style appearance with ref images'**
  String get helpFeatureDirectorRefDesc;

  /// No description provided for @helpFeatureVibeTransfer.
  ///
  /// In en, this message translates to:
  /// **'Vibe Transfer'**
  String get helpFeatureVibeTransfer;

  /// No description provided for @helpFeatureVibeTransferDesc.
  ///
  /// In en, this message translates to:
  /// **'Influence composition & mood with ref images'**
  String get helpFeatureVibeTransferDesc;

  /// No description provided for @helpFeatureCascade.
  ///
  /// In en, this message translates to:
  /// **'Cascade'**
  String get helpFeatureCascade;

  /// No description provided for @helpFeatureCascadeDesc.
  ///
  /// In en, this message translates to:
  /// **'Multi-beat sequential scene generation'**
  String get helpFeatureCascadeDesc;

  /// No description provided for @helpFeatureImg2img.
  ///
  /// In en, this message translates to:
  /// **'IMG2IMG'**
  String get helpFeatureImg2img;

  /// No description provided for @helpFeatureImg2imgDesc.
  ///
  /// In en, this message translates to:
  /// **'Edit/refine images with inpainting & variation'**
  String get helpFeatureImg2imgDesc;

  /// No description provided for @helpFeatureThemes.
  ///
  /// In en, this message translates to:
  /// **'Themes'**
  String get helpFeatureThemes;

  /// No description provided for @helpFeatureThemesDesc.
  ///
  /// In en, this message translates to:
  /// **'Customize all colors, fonts, and scale'**
  String get helpFeatureThemesDesc;

  /// No description provided for @helpFeaturePacks.
  ///
  /// In en, this message translates to:
  /// **'Packs'**
  String get helpFeaturePacks;

  /// No description provided for @helpFeaturePacksDesc.
  ///
  /// In en, this message translates to:
  /// **'Export/import presets, styles, wildcards as .vpack'**
  String get helpFeaturePacksDesc;

  /// No description provided for @wildcardManager.
  ///
  /// In en, this message translates to:
  /// **'WILDCARD MANAGER'**
  String get wildcardManager;

  /// No description provided for @wildcardManageDesc.
  ///
  /// In en, this message translates to:
  /// **'MANAGE AND EDIT YOUR WILDCARD FILES'**
  String get wildcardManageDesc;

  /// No description provided for @wildcardFiles.
  ///
  /// In en, this message translates to:
  /// **'FILES'**
  String get wildcardFiles;

  /// No description provided for @wildcardNew.
  ///
  /// In en, this message translates to:
  /// **'NEW WILDCARD'**
  String get wildcardNew;

  /// No description provided for @wildcardSelectOrCreate.
  ///
  /// In en, this message translates to:
  /// **'SELECT OR CREATE A WILDCARD FILE'**
  String get wildcardSelectOrCreate;

  /// No description provided for @wildcardValidateTags.
  ///
  /// In en, this message translates to:
  /// **'VALIDATE TAGS'**
  String get wildcardValidateTags;

  /// No description provided for @wildcardRecognized.
  ///
  /// In en, this message translates to:
  /// **'{valid}/{total} RECOGNIZED'**
  String wildcardRecognized(int valid, int total);

  /// No description provided for @wildcardClear.
  ///
  /// In en, this message translates to:
  /// **'CLEAR'**
  String get wildcardClear;

  /// No description provided for @wildcardStartTyping.
  ///
  /// In en, this message translates to:
  /// **'START TYPING TAGS...'**
  String get wildcardStartTyping;

  /// No description provided for @wildcardUnrecognized.
  ///
  /// In en, this message translates to:
  /// **'{count} UNRECOGNIZED'**
  String wildcardUnrecognized(int count);

  /// No description provided for @wildcardCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'CREATE WILDCARD'**
  String get wildcardCreateTitle;

  /// No description provided for @wildcardFileName.
  ///
  /// In en, this message translates to:
  /// **'FILE NAME'**
  String get wildcardFileName;

  /// No description provided for @wildcardHelp.
  ///
  /// In en, this message translates to:
  /// **'WILDCARD HELP'**
  String get wildcardHelp;

  /// No description provided for @wildcardHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'WILDCARD HELP'**
  String get wildcardHelpTitle;

  /// No description provided for @wildcardHelpRandom.
  ///
  /// In en, this message translates to:
  /// **'__name__ picks a random line from that wildcard file'**
  String get wildcardHelpRandom;

  /// No description provided for @wildcardHelpDotSyntax.
  ///
  /// In en, this message translates to:
  /// **'Use dots for multi-word names'**
  String get wildcardHelpDotSyntax;

  /// No description provided for @wildcardHelpBrowse.
  ///
  /// In en, this message translates to:
  /// **'Type __ to browse and insert a wildcard from autocomplete'**
  String get wildcardHelpBrowse;

  /// No description provided for @wildcardHelpNesting.
  ///
  /// In en, this message translates to:
  /// **'Nesting'**
  String get wildcardHelpNesting;

  /// No description provided for @wildcardHelpNestingDesc.
  ///
  /// In en, this message translates to:
  /// **'Wildcards can reference other wildcards (up to 5 levels deep)'**
  String get wildcardHelpNestingDesc;

  /// No description provided for @wildcardHelpTip.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder files — the order is used in autocomplete'**
  String get wildcardHelpTip;

  /// No description provided for @wildcardMode.
  ///
  /// In en, this message translates to:
  /// **'MODE'**
  String get wildcardMode;

  /// No description provided for @wildcardModeRandom.
  ///
  /// In en, this message translates to:
  /// **'RANDOM'**
  String get wildcardModeRandom;

  /// No description provided for @wildcardModeRandomDesc.
  ///
  /// In en, this message translates to:
  /// **'Picks a random line each time the wildcard is used'**
  String get wildcardModeRandomDesc;

  /// No description provided for @wildcardModeSequential.
  ///
  /// In en, this message translates to:
  /// **'SEQUENTIAL'**
  String get wildcardModeSequential;

  /// No description provided for @wildcardModeSequentialDesc.
  ///
  /// In en, this message translates to:
  /// **'Cycles through lines in order, looping back to the start'**
  String get wildcardModeSequentialDesc;

  /// No description provided for @wildcardModeShuffle.
  ///
  /// In en, this message translates to:
  /// **'SHUFFLE'**
  String get wildcardModeShuffle;

  /// No description provided for @wildcardModeShuffleDesc.
  ///
  /// In en, this message translates to:
  /// **'Shuffles all lines randomly, then cycles through without repeats'**
  String get wildcardModeShuffleDesc;

  /// No description provided for @wildcardModeWeighted.
  ///
  /// In en, this message translates to:
  /// **'WEIGHTED'**
  String get wildcardModeWeighted;

  /// No description provided for @wildcardModeWeightedDesc.
  ///
  /// In en, this message translates to:
  /// **'Uses weight syntax (e.g. 10::option) to bias selection probability'**
  String get wildcardModeWeightedDesc;

  /// No description provided for @wildcardHelpFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorited wildcards appear with a gold outline in tag completion'**
  String get wildcardHelpFavorites;

  /// No description provided for @wildcardDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'DELETE WILDCARD'**
  String get wildcardDeleteTitle;

  /// No description provided for @wildcardDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \'\'{name}\'\'?'**
  String wildcardDeleteConfirm(String name);

  /// No description provided for @wildcardRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'RENAME WILDCARD'**
  String get wildcardRenameTitle;

  /// No description provided for @wildcardRenameExists.
  ///
  /// In en, this message translates to:
  /// **'A wildcard with this name already exists'**
  String get wildcardRenameExists;

  /// No description provided for @tagLibTitle.
  ///
  /// In en, this message translates to:
  /// **'TAG LIBRARY'**
  String get tagLibTitle;

  /// No description provided for @tagLibPreviewSettings.
  ///
  /// In en, this message translates to:
  /// **'PREVIEW SETTINGS'**
  String get tagLibPreviewSettings;

  /// No description provided for @tagLibAddTag.
  ///
  /// In en, this message translates to:
  /// **'ADD TAG'**
  String get tagLibAddTag;

  /// No description provided for @tagLibSearchTags.
  ///
  /// In en, this message translates to:
  /// **'SEARCH TAGS...'**
  String get tagLibSearchTags;

  /// No description provided for @tagLibAll.
  ///
  /// In en, this message translates to:
  /// **'ALL'**
  String get tagLibAll;

  /// No description provided for @tagLibFavorites.
  ///
  /// In en, this message translates to:
  /// **'FAVORITES'**
  String get tagLibFavorites;

  /// No description provided for @tagLibImages.
  ///
  /// In en, this message translates to:
  /// **'IMAGES'**
  String get tagLibImages;

  /// No description provided for @tagLibSort.
  ///
  /// In en, this message translates to:
  /// **'SORT:'**
  String get tagLibSort;

  /// No description provided for @tagLibSortCountDesc.
  ///
  /// In en, this message translates to:
  /// **'COUNT ↓'**
  String get tagLibSortCountDesc;

  /// No description provided for @tagLibSortCountAsc.
  ///
  /// In en, this message translates to:
  /// **'COUNT ↑'**
  String get tagLibSortCountAsc;

  /// No description provided for @tagLibSortAZ.
  ///
  /// In en, this message translates to:
  /// **'A-Z'**
  String get tagLibSortAZ;

  /// No description provided for @tagLibSortZA.
  ///
  /// In en, this message translates to:
  /// **'Z-A'**
  String get tagLibSortZA;

  /// No description provided for @tagLibSortFavsFirst.
  ///
  /// In en, this message translates to:
  /// **'FAVS FIRST'**
  String get tagLibSortFavsFirst;

  /// No description provided for @tagLibTagCount.
  ///
  /// In en, this message translates to:
  /// **'{count} TAGS'**
  String tagLibTagCount(int count);

  /// No description provided for @tagLibDeleteTag.
  ///
  /// In en, this message translates to:
  /// **'DELETE TAG'**
  String get tagLibDeleteTag;

  /// No description provided for @tagLibRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'REMOVE \'{tag}\' FROM LIBRARY?'**
  String tagLibRemoveConfirm(String tag);

  /// No description provided for @tagLibTestTag.
  ///
  /// In en, this message translates to:
  /// **'TEST TAG'**
  String get tagLibTestTag;

  /// No description provided for @tagLibAddNewTag.
  ///
  /// In en, this message translates to:
  /// **'ADD NEW TAG'**
  String get tagLibAddNewTag;

  /// No description provided for @tagLibTagName.
  ///
  /// In en, this message translates to:
  /// **'TAG NAME'**
  String get tagLibTagName;

  /// No description provided for @tagLibCount.
  ///
  /// In en, this message translates to:
  /// **'COUNT'**
  String get tagLibCount;

  /// No description provided for @tagLibAddTagBtn.
  ///
  /// In en, this message translates to:
  /// **'ADD TAG'**
  String get tagLibAddTagBtn;

  /// No description provided for @tagLibDeleteExample.
  ///
  /// In en, this message translates to:
  /// **'DELETE EXAMPLE'**
  String get tagLibDeleteExample;

  /// No description provided for @tagLibDeleteExampleConfirm.
  ///
  /// In en, this message translates to:
  /// **'DELETE THIS VISUAL EXAMPLE?'**
  String get tagLibDeleteExampleConfirm;

  /// No description provided for @tagLibTesting.
  ///
  /// In en, this message translates to:
  /// **'TESTING: {tag}'**
  String tagLibTesting(String tag);

  /// No description provided for @tagLibGeneratingPreview.
  ///
  /// In en, this message translates to:
  /// **'GENERATING PREVIEW...'**
  String get tagLibGeneratingPreview;

  /// No description provided for @tagLibGenerationFailed.
  ///
  /// In en, this message translates to:
  /// **'GENERATION FAILED'**
  String get tagLibGenerationFailed;

  /// No description provided for @tagLibExampleSaved.
  ///
  /// In en, this message translates to:
  /// **'EXAMPLE SAVED'**
  String get tagLibExampleSaved;

  /// No description provided for @tagLibSaveAsExample.
  ///
  /// In en, this message translates to:
  /// **'SAVE AS EXAMPLE'**
  String get tagLibSaveAsExample;

  /// No description provided for @tagLibPreviewSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'PREVIEW SETTINGS'**
  String get tagLibPreviewSettingsTitle;

  /// No description provided for @tagLibPositivePromptBase.
  ///
  /// In en, this message translates to:
  /// **'POSITIVE PROMPT (BASE)'**
  String get tagLibPositivePromptBase;

  /// No description provided for @tagLibNegativePrompt.
  ///
  /// In en, this message translates to:
  /// **'NEGATIVE PROMPT'**
  String get tagLibNegativePrompt;

  /// No description provided for @tagLibSampler.
  ///
  /// In en, this message translates to:
  /// **'SAMPLER'**
  String get tagLibSampler;

  /// No description provided for @tagLibSteps.
  ///
  /// In en, this message translates to:
  /// **'STEPS'**
  String get tagLibSteps;

  /// No description provided for @tagLibWidth.
  ///
  /// In en, this message translates to:
  /// **'WIDTH'**
  String get tagLibWidth;

  /// No description provided for @tagLibHeight.
  ///
  /// In en, this message translates to:
  /// **'HEIGHT'**
  String get tagLibHeight;

  /// No description provided for @tagLibScale.
  ///
  /// In en, this message translates to:
  /// **'SCALE'**
  String get tagLibScale;

  /// No description provided for @tagLibSeed.
  ///
  /// In en, this message translates to:
  /// **'SEED'**
  String get tagLibSeed;

  /// No description provided for @tagLibRandom.
  ///
  /// In en, this message translates to:
  /// **'RANDOM'**
  String get tagLibRandom;

  /// No description provided for @tagDetailViewOnDanbooru.
  ///
  /// In en, this message translates to:
  /// **'View on Danbooru'**
  String get tagDetailViewOnDanbooru;

  /// No description provided for @tagDetailNoWiki.
  ///
  /// In en, this message translates to:
  /// **'No wiki description for this tag.'**
  String get tagDetailNoWiki;

  /// No description provided for @tagDetailCheckDanbooru.
  ///
  /// In en, this message translates to:
  /// **'Check on Danbooru'**
  String get tagDetailCheckDanbooru;

  /// No description provided for @tagDetailLicense.
  ///
  /// In en, this message translates to:
  /// **'Tag descriptions © Danbooru contributors, CC-BY-SA-4.0'**
  String get tagDetailLicense;

  /// No description provided for @presetManager.
  ///
  /// In en, this message translates to:
  /// **'PRESET MANAGER'**
  String get presetManager;

  /// No description provided for @presetManageDesc.
  ///
  /// In en, this message translates to:
  /// **'MANAGE AND EDIT YOUR GENERATION PRESETS'**
  String get presetManageDesc;

  /// No description provided for @presetList.
  ///
  /// In en, this message translates to:
  /// **'PRESETS'**
  String get presetList;

  /// No description provided for @presetNew.
  ///
  /// In en, this message translates to:
  /// **'NEW PRESET'**
  String get presetNew;

  /// No description provided for @presetCharsInfo.
  ///
  /// In en, this message translates to:
  /// **'{chars} CHARS, {ints} INTS'**
  String presetCharsInfo(int chars, int ints);

  /// No description provided for @presetCharsRefsInfo.
  ///
  /// In en, this message translates to:
  /// **'{chars} CHARS, {ints} INTS, {refs} REFS'**
  String presetCharsRefsInfo(int chars, int ints, int refs);

  /// No description provided for @presetSelectToEdit.
  ///
  /// In en, this message translates to:
  /// **'SELECT A PRESET TO EDIT'**
  String get presetSelectToEdit;

  /// No description provided for @presetIdentity.
  ///
  /// In en, this message translates to:
  /// **'IDENTITY'**
  String get presetIdentity;

  /// No description provided for @presetName.
  ///
  /// In en, this message translates to:
  /// **'NAME'**
  String get presetName;

  /// No description provided for @presetPrompts.
  ///
  /// In en, this message translates to:
  /// **'PROMPTS'**
  String get presetPrompts;

  /// No description provided for @presetPrompt.
  ///
  /// In en, this message translates to:
  /// **'PROMPT'**
  String get presetPrompt;

  /// No description provided for @presetNegativePrompt.
  ///
  /// In en, this message translates to:
  /// **'NEGATIVE PROMPT'**
  String get presetNegativePrompt;

  /// No description provided for @presetGenSettings.
  ///
  /// In en, this message translates to:
  /// **'GENERATION SETTINGS'**
  String get presetGenSettings;

  /// No description provided for @presetWidth.
  ///
  /// In en, this message translates to:
  /// **'WIDTH'**
  String get presetWidth;

  /// No description provided for @presetHeight.
  ///
  /// In en, this message translates to:
  /// **'HEIGHT'**
  String get presetHeight;

  /// No description provided for @presetScale.
  ///
  /// In en, this message translates to:
  /// **'SCALE'**
  String get presetScale;

  /// No description provided for @presetSteps.
  ///
  /// In en, this message translates to:
  /// **'STEPS'**
  String get presetSteps;

  /// No description provided for @presetSampler.
  ///
  /// In en, this message translates to:
  /// **'SAMPLER'**
  String get presetSampler;

  /// No description provided for @presetCharsAndInteractions.
  ///
  /// In en, this message translates to:
  /// **'CHARACTERS & INTERACTIONS'**
  String get presetCharsAndInteractions;

  /// No description provided for @presetNoChars.
  ///
  /// In en, this message translates to:
  /// **'NO CHARACTERS SAVED IN THIS PRESET'**
  String get presetNoChars;

  /// No description provided for @presetCharacterN.
  ///
  /// In en, this message translates to:
  /// **'CHARACTER {n}'**
  String presetCharacterN(int n);

  /// No description provided for @presetInteractions.
  ///
  /// In en, this message translates to:
  /// **'INTERACTIONS'**
  String get presetInteractions;

  /// No description provided for @presetReferences.
  ///
  /// In en, this message translates to:
  /// **'REFERENCES'**
  String get presetReferences;

  /// No description provided for @presetNoRefs.
  ///
  /// In en, this message translates to:
  /// **'NO REFERENCES SAVED IN THIS PRESET'**
  String get presetNoRefs;

  /// No description provided for @presetProcessing.
  ///
  /// In en, this message translates to:
  /// **'PROCESSING...'**
  String get presetProcessing;

  /// No description provided for @presetAddReference.
  ///
  /// In en, this message translates to:
  /// **'ADD REFERENCE'**
  String get presetAddReference;

  /// No description provided for @presetDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'DELETE PRESET'**
  String get presetDeleteTitle;

  /// No description provided for @presetDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'ARE YOU SURE YOU WANT TO DELETE \'\'{name}\'\'?'**
  String presetDeleteConfirm(String name);

  /// No description provided for @presetOverwriteTitle.
  ///
  /// In en, this message translates to:
  /// **'OVERWRITE PRESET'**
  String get presetOverwriteTitle;

  /// No description provided for @presetOverwriteConfirm.
  ///
  /// In en, this message translates to:
  /// **'A PRESET WITH THE NAME \'\'{name}\'\' ALREADY EXISTS. OVERWRITE?'**
  String presetOverwriteConfirm(String name);

  /// No description provided for @styleEditor.
  ///
  /// In en, this message translates to:
  /// **'STYLE EDITOR'**
  String get styleEditor;

  /// No description provided for @styleManageDesc.
  ///
  /// In en, this message translates to:
  /// **'MANAGE PROMPT SNIPPETS AND STYLE TAGS'**
  String get styleManageDesc;

  /// No description provided for @styleList.
  ///
  /// In en, this message translates to:
  /// **'STYLES'**
  String get styleList;

  /// No description provided for @styleNew.
  ///
  /// In en, this message translates to:
  /// **'NEW STYLE'**
  String get styleNew;

  /// No description provided for @styleResetDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset styles to defaults'**
  String get styleResetDefaults;

  /// No description provided for @styleSelectToEdit.
  ///
  /// In en, this message translates to:
  /// **'SELECT A STYLE TO EDIT'**
  String get styleSelectToEdit;

  /// No description provided for @styleIdentity.
  ///
  /// In en, this message translates to:
  /// **'IDENTITY'**
  String get styleIdentity;

  /// No description provided for @styleName.
  ///
  /// In en, this message translates to:
  /// **'NAME'**
  String get styleName;

  /// No description provided for @styleDefaultOnLaunch.
  ///
  /// In en, this message translates to:
  /// **'DEFAULT ON LAUNCH'**
  String get styleDefaultOnLaunch;

  /// No description provided for @styleTargetPrompt.
  ///
  /// In en, this message translates to:
  /// **'TARGET PROMPT'**
  String get styleTargetPrompt;

  /// No description provided for @stylePositive.
  ///
  /// In en, this message translates to:
  /// **'POSITIVE'**
  String get stylePositive;

  /// No description provided for @styleNegative.
  ///
  /// In en, this message translates to:
  /// **'NEGATIVE'**
  String get styleNegative;

  /// No description provided for @styleNegativeContent.
  ///
  /// In en, this message translates to:
  /// **'NEGATIVE CONTENT'**
  String get styleNegativeContent;

  /// No description provided for @stylePositiveContent.
  ///
  /// In en, this message translates to:
  /// **'POSITIVE CONTENT'**
  String get stylePositiveContent;

  /// No description provided for @styleContent.
  ///
  /// In en, this message translates to:
  /// **'CONTENT'**
  String get styleContent;

  /// No description provided for @stylePlacement.
  ///
  /// In en, this message translates to:
  /// **'PLACEMENT'**
  String get stylePlacement;

  /// No description provided for @styleBeginningPrefix.
  ///
  /// In en, this message translates to:
  /// **'BEGINNING (PREFIX)'**
  String get styleBeginningPrefix;

  /// No description provided for @styleEndSuffix.
  ///
  /// In en, this message translates to:
  /// **'END (SUFFIX)'**
  String get styleEndSuffix;

  /// No description provided for @styleDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'DELETE STYLE'**
  String get styleDeleteTitle;

  /// No description provided for @styleDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'ARE YOU SURE YOU WANT TO DELETE \'\'{name}\'\'?'**
  String styleDeleteConfirm(String name);

  /// No description provided for @styleOverwriteTitle.
  ///
  /// In en, this message translates to:
  /// **'OVERWRITE STYLE'**
  String get styleOverwriteTitle;

  /// No description provided for @styleOverwriteConfirm.
  ///
  /// In en, this message translates to:
  /// **'A STYLE WITH THE NAME \'\'{name}\'\' ALREADY EXISTS. OVERWRITE?'**
  String styleOverwriteConfirm(String name);

  /// No description provided for @refPreciseReferences.
  ///
  /// In en, this message translates to:
  /// **'PRECISE REFERENCES'**
  String get refPreciseReferences;

  /// No description provided for @refShortLabel.
  ///
  /// In en, this message translates to:
  /// **'REF'**
  String get refShortLabel;

  /// No description provided for @refVibeTransfer.
  ///
  /// In en, this message translates to:
  /// **'VIBE TRANSFER'**
  String get refVibeTransfer;

  /// No description provided for @refNameHint.
  ///
  /// In en, this message translates to:
  /// **'NAME'**
  String get refNameHint;

  /// No description provided for @refClearAll.
  ///
  /// In en, this message translates to:
  /// **'CLEAR ALL'**
  String get refClearAll;

  /// No description provided for @refSavedSection.
  ///
  /// In en, this message translates to:
  /// **'SAVED'**
  String get refSavedSection;

  /// No description provided for @refSaveReference.
  ///
  /// In en, this message translates to:
  /// **'SAVE REFERENCE'**
  String get refSaveReference;

  /// No description provided for @refReferenceCount.
  ///
  /// In en, this message translates to:
  /// **'{count} REFERENCES'**
  String refReferenceCount(int count);

  /// No description provided for @refNoReferencesAdded.
  ///
  /// In en, this message translates to:
  /// **'NO REFERENCES ADDED'**
  String get refNoReferencesAdded;

  /// No description provided for @refEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'Upload reference images to maintain character\nappearance or artistic style across generations.'**
  String get refEmptyDescription;

  /// No description provided for @refAddReference.
  ///
  /// In en, this message translates to:
  /// **'ADD REFERENCE'**
  String get refAddReference;

  /// No description provided for @refEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'REFERENCE EDITOR'**
  String get refEditorTitle;

  /// No description provided for @refTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'REFERENCE TYPE'**
  String get refTypeLabel;

  /// No description provided for @refStrength.
  ///
  /// In en, this message translates to:
  /// **'STRENGTH'**
  String get refStrength;

  /// No description provided for @refFidelity.
  ///
  /// In en, this message translates to:
  /// **'FIDELITY'**
  String get refFidelity;

  /// No description provided for @refStrengthShort.
  ///
  /// In en, this message translates to:
  /// **'STR'**
  String get refStrengthShort;

  /// No description provided for @refFidelityShort.
  ///
  /// In en, this message translates to:
  /// **'FID'**
  String get refFidelityShort;

  /// No description provided for @refTypeCharacter.
  ///
  /// In en, this message translates to:
  /// **'CHARACTER'**
  String get refTypeCharacter;

  /// No description provided for @refTypeStyle.
  ///
  /// In en, this message translates to:
  /// **'STYLE'**
  String get refTypeStyle;

  /// No description provided for @refTypeCharAndStyle.
  ///
  /// In en, this message translates to:
  /// **'CHAR & STYLE'**
  String get refTypeCharAndStyle;

  /// No description provided for @refSaveVibe.
  ///
  /// In en, this message translates to:
  /// **'SAVE VIBE'**
  String get refSaveVibe;

  /// No description provided for @refVibeCount.
  ///
  /// In en, this message translates to:
  /// **'{count} VIBES'**
  String refVibeCount(int count);

  /// No description provided for @refNoVibesAdded.
  ///
  /// In en, this message translates to:
  /// **'NO VIBES ADDED'**
  String get refNoVibesAdded;

  /// No description provided for @refVibeEmptyDescription.
  ///
  /// In en, this message translates to:
  /// **'Upload reference images to transfer artistic\nstyle and mood to your generations.'**
  String get refVibeEmptyDescription;

  /// No description provided for @refAddVibe.
  ///
  /// In en, this message translates to:
  /// **'ADD VIBE'**
  String get refAddVibe;

  /// No description provided for @refVibeLabel.
  ///
  /// In en, this message translates to:
  /// **'VIBE'**
  String get refVibeLabel;

  /// No description provided for @refVibeRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this vibe from the list?'**
  String get refVibeRemoveConfirm;

  /// No description provided for @refVibeEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'VIBE EDITOR'**
  String get refVibeEditorTitle;

  /// No description provided for @refInfoExtracted.
  ///
  /// In en, this message translates to:
  /// **'INFO EXTRACTED'**
  String get refInfoExtracted;

  /// No description provided for @refInfoExtractedShort.
  ///
  /// In en, this message translates to:
  /// **'INF'**
  String get refInfoExtractedShort;

  /// No description provided for @refApiKeyMissing.
  ///
  /// In en, this message translates to:
  /// **'API key missing or invalid'**
  String get refApiKeyMissing;

  /// No description provided for @refImageProcessFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read this image. Try another file.'**
  String get refImageProcessFailed;

  /// No description provided for @refVibeNoPermission.
  ///
  /// In en, this message translates to:
  /// **'Your account is not allowed to encode vibes.'**
  String get refVibeNoPermission;

  /// No description provided for @refErrorPointsInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Not enough points to encode this vibe.'**
  String get refErrorPointsInsufficient;

  /// No description provided for @refErrorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Sign in again.'**
  String get refErrorSessionExpired;

  /// No description provided for @refErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error. Check your connection and try again.'**
  String get refErrorNetwork;

  /// No description provided for @refErrorServiceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The service is busy or unavailable. Try again later.'**
  String get refErrorServiceUnavailable;

  /// No description provided for @refVibeEncodeFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not encode this vibe. Try again later.'**
  String get refVibeEncodeFailed;

  /// No description provided for @refLoadSaved.
  ///
  /// In en, this message translates to:
  /// **'LOAD SAVED'**
  String get refLoadSaved;

  /// No description provided for @refPickImage.
  ///
  /// In en, this message translates to:
  /// **'PICK IMAGE'**
  String get refPickImage;

  /// No description provided for @refBrowseFiles.
  ///
  /// In en, this message translates to:
  /// **'BROWSE FILES'**
  String get refBrowseFiles;

  /// No description provided for @refNoSavedRefs.
  ///
  /// In en, this message translates to:
  /// **'NO SAVED REFERENCES'**
  String get refNoSavedRefs;

  /// No description provided for @refRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get refRemove;

  /// No description provided for @refLibrarySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to the library'**
  String get refLibrarySaved;

  /// No description provided for @refLibrarySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update the library. Storage may be full.'**
  String get refLibrarySaveFailed;

  /// No description provided for @packTitle.
  ///
  /// In en, this message translates to:
  /// **'NAIWEAVER PACKS'**
  String get packTitle;

  /// No description provided for @packDesc.
  ///
  /// In en, this message translates to:
  /// **'Export and import presets, styles, and wildcards as .vpack files.'**
  String get packDesc;

  /// No description provided for @packExportLabel.
  ///
  /// In en, this message translates to:
  /// **'EXPORT PACK'**
  String get packExportLabel;

  /// No description provided for @packExportDesc.
  ///
  /// In en, this message translates to:
  /// **'Bundle presets, styles, and wildcards'**
  String get packExportDesc;

  /// No description provided for @packImportLabel.
  ///
  /// In en, this message translates to:
  /// **'IMPORT PACK'**
  String get packImportLabel;

  /// No description provided for @packImportDesc.
  ///
  /// In en, this message translates to:
  /// **'Load a .vpack file'**
  String get packImportDesc;

  /// No description provided for @packGalleryExport.
  ///
  /// In en, this message translates to:
  /// **'GALLERY EXPORT'**
  String get packGalleryExport;

  /// No description provided for @packGalleryExportDesc.
  ///
  /// In en, this message translates to:
  /// **'Export gallery images as a ZIP file, organized by album folders.'**
  String get packGalleryExportDesc;

  /// No description provided for @packExportGalleryZip.
  ///
  /// In en, this message translates to:
  /// **'EXPORT GALLERY AS ZIP'**
  String get packExportGalleryZip;

  /// No description provided for @packExportGalleryZipDesc.
  ///
  /// In en, this message translates to:
  /// **'Preserve album hierarchy in folders'**
  String get packExportGalleryZipDesc;

  /// No description provided for @packFailedRead.
  ///
  /// In en, this message translates to:
  /// **'Failed to read pack: {error}'**
  String packFailedRead(String error);

  /// No description provided for @packExportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'EXPORT PACK'**
  String get packExportDialogTitle;

  /// No description provided for @packName.
  ///
  /// In en, this message translates to:
  /// **'PACK NAME'**
  String get packName;

  /// No description provided for @packDescriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'DESCRIPTION (OPTIONAL)'**
  String get packDescriptionOptional;

  /// No description provided for @packPresetsSection.
  ///
  /// In en, this message translates to:
  /// **'PRESETS ({selected}/{total})'**
  String packPresetsSection(int selected, int total);

  /// No description provided for @packStylesSection.
  ///
  /// In en, this message translates to:
  /// **'STYLES ({selected}/{total})'**
  String packStylesSection(int selected, int total);

  /// No description provided for @packWildcardsSection.
  ///
  /// In en, this message translates to:
  /// **'WILDCARDS ({selected}/{total})'**
  String packWildcardsSection(int selected, int total);

  /// No description provided for @packSavedRefsSection.
  ///
  /// In en, this message translates to:
  /// **'SAVED REFERENCES ({selected}/{total})'**
  String packSavedRefsSection(int selected, int total);

  /// No description provided for @packSavedVibesSection.
  ///
  /// In en, this message translates to:
  /// **'SAVED VIBES ({selected}/{total})'**
  String packSavedVibesSection(int selected, int total);

  /// No description provided for @packCharacterPresetsSection.
  ///
  /// In en, this message translates to:
  /// **'CHARACTER PRESETS ({selected}/{total})'**
  String packCharacterPresetsSection(int selected, int total);

  /// No description provided for @packThemesSection.
  ///
  /// In en, this message translates to:
  /// **'THEMES ({selected}/{total})'**
  String packThemesSection(int selected, int total);

  /// No description provided for @packAlbumsSection.
  ///
  /// In en, this message translates to:
  /// **'ALBUMS ({selected}/{total})'**
  String packAlbumsSection(int selected, int total);

  /// No description provided for @packSettingsSection.
  ///
  /// In en, this message translates to:
  /// **'APP & JUKEBOX SETTINGS'**
  String get packSettingsSection;

  /// No description provided for @packSettingsItem.
  ///
  /// In en, this message translates to:
  /// **'App & jukebox settings'**
  String get packSettingsItem;

  /// No description provided for @packImportRestartHint.
  ///
  /// In en, this message translates to:
  /// **'Imported. Restart the app to fully apply settings and themes.'**
  String get packImportRestartHint;

  /// No description provided for @packExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Pack exported successfully'**
  String get packExportSuccess;

  /// No description provided for @packExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String packExportFailed(String error);

  /// No description provided for @packImportDialogTitle2.
  ///
  /// In en, this message translates to:
  /// **'IMPORT PACK'**
  String get packImportDialogTitle2;

  /// No description provided for @packImportCount.
  ///
  /// In en, this message translates to:
  /// **'IMPORT ({count})'**
  String packImportCount(int count);

  /// No description provided for @packImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Pack imported successfully'**
  String get packImportSuccess;

  /// No description provided for @packImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String packImportFailed(String error);

  /// No description provided for @packRefLibrarySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'The saved references could not be stored. Free up storage space and import again.'**
  String get packRefLibrarySaveFailed;

  /// No description provided for @packSelectAll.
  ///
  /// In en, this message translates to:
  /// **'ALL'**
  String get packSelectAll;

  /// No description provided for @packSelectNone.
  ///
  /// In en, this message translates to:
  /// **'NONE'**
  String get packSelectNone;

  /// No description provided for @packExportGalleryTitle.
  ///
  /// In en, this message translates to:
  /// **'EXPORT GALLERY'**
  String get packExportGalleryTitle;

  /// No description provided for @packAlbums.
  ///
  /// In en, this message translates to:
  /// **'ALBUMS'**
  String get packAlbums;

  /// No description provided for @packUnsortedCount.
  ///
  /// In en, this message translates to:
  /// **'UNSORTED ({count})'**
  String packUnsortedCount(int count);

  /// No description provided for @packOptions.
  ///
  /// In en, this message translates to:
  /// **'OPTIONS'**
  String get packOptions;

  /// No description provided for @packStripMetadata.
  ///
  /// In en, this message translates to:
  /// **'STRIP METADATA'**
  String get packStripMetadata;

  /// No description provided for @packFavoritesOnly.
  ///
  /// In en, this message translates to:
  /// **'FAVORITES ONLY'**
  String get packFavoritesOnly;

  /// No description provided for @packExportCount.
  ///
  /// In en, this message translates to:
  /// **'EXPORT ({count})'**
  String packExportCount(int count);

  /// No description provided for @packSaveDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Save NAIWeaver Pack'**
  String get packSaveDialogTitle;

  /// No description provided for @packExportGalleryZipDialog.
  ///
  /// In en, this message translates to:
  /// **'Export Gallery ZIP'**
  String get packExportGalleryZipDialog;

  /// No description provided for @packExportedToZip.
  ///
  /// In en, this message translates to:
  /// **'Exported {count} images to ZIP'**
  String packExportedToZip(int count);

  /// No description provided for @themeSelectToEdit.
  ///
  /// In en, this message translates to:
  /// **'SELECT A THEME TO EDIT'**
  String get themeSelectToEdit;

  /// No description provided for @themeList.
  ///
  /// In en, this message translates to:
  /// **'THEMES'**
  String get themeList;

  /// No description provided for @themeNew.
  ///
  /// In en, this message translates to:
  /// **'New Theme'**
  String get themeNew;

  /// No description provided for @themeSave.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get themeSave;

  /// No description provided for @themeReset.
  ///
  /// In en, this message translates to:
  /// **'RESET'**
  String get themeReset;

  /// No description provided for @themePreview.
  ///
  /// In en, this message translates to:
  /// **'PREVIEW'**
  String get themePreview;

  /// No description provided for @themeColors.
  ///
  /// In en, this message translates to:
  /// **'COLORS'**
  String get themeColors;

  /// No description provided for @themeColorBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get themeColorBackground;

  /// No description provided for @themeColorSurfaceHigh.
  ///
  /// In en, this message translates to:
  /// **'Surface High'**
  String get themeColorSurfaceHigh;

  /// No description provided for @themeColorSurfaceMid.
  ///
  /// In en, this message translates to:
  /// **'Surface Mid'**
  String get themeColorSurfaceMid;

  /// No description provided for @themeColorTextPrimary.
  ///
  /// In en, this message translates to:
  /// **'Text Primary'**
  String get themeColorTextPrimary;

  /// No description provided for @themeColorTextSecondary.
  ///
  /// In en, this message translates to:
  /// **'Text Secondary'**
  String get themeColorTextSecondary;

  /// No description provided for @themeColorTextTertiary.
  ///
  /// In en, this message translates to:
  /// **'Text Tertiary'**
  String get themeColorTextTertiary;

  /// No description provided for @themeColorTextDisabled.
  ///
  /// In en, this message translates to:
  /// **'Text Disabled'**
  String get themeColorTextDisabled;

  /// No description provided for @themeColorTextMinimal.
  ///
  /// In en, this message translates to:
  /// **'Text Minimal'**
  String get themeColorTextMinimal;

  /// No description provided for @themeColorBorderStrong.
  ///
  /// In en, this message translates to:
  /// **'Border Strong'**
  String get themeColorBorderStrong;

  /// No description provided for @themeColorBorderMedium.
  ///
  /// In en, this message translates to:
  /// **'Border Medium'**
  String get themeColorBorderMedium;

  /// No description provided for @themeColorBorderSubtle.
  ///
  /// In en, this message translates to:
  /// **'Border Subtle'**
  String get themeColorBorderSubtle;

  /// No description provided for @themeColorAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get themeColorAccent;

  /// No description provided for @themeColorAccentEdit.
  ///
  /// In en, this message translates to:
  /// **'Accent Edit'**
  String get themeColorAccentEdit;

  /// No description provided for @themeColorAccentSuccess.
  ///
  /// In en, this message translates to:
  /// **'Accent Success'**
  String get themeColorAccentSuccess;

  /// No description provided for @themeColorAccentDanger.
  ///
  /// In en, this message translates to:
  /// **'Accent Danger'**
  String get themeColorAccentDanger;

  /// No description provided for @themeColorLogo.
  ///
  /// In en, this message translates to:
  /// **'Logo'**
  String get themeColorLogo;

  /// No description provided for @themeColorCascade.
  ///
  /// In en, this message translates to:
  /// **'Cascade'**
  String get themeColorCascade;

  /// No description provided for @themeReferences.
  ///
  /// In en, this message translates to:
  /// **'REFERENCES'**
  String get themeReferences;

  /// No description provided for @themeColorVibeTransfer.
  ///
  /// In en, this message translates to:
  /// **'Vibe Transfer'**
  String get themeColorVibeTransfer;

  /// No description provided for @themeColorRefCharacter.
  ///
  /// In en, this message translates to:
  /// **'Ref Character'**
  String get themeColorRefCharacter;

  /// No description provided for @themeColorRefStyle.
  ///
  /// In en, this message translates to:
  /// **'Ref Style'**
  String get themeColorRefStyle;

  /// No description provided for @themeColorRefCharStyle.
  ///
  /// In en, this message translates to:
  /// **'Ref Char+Style'**
  String get themeColorRefCharStyle;

  /// No description provided for @themeColorFavorite.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get themeColorFavorite;

  /// No description provided for @themeColorCharacter.
  ///
  /// In en, this message translates to:
  /// **'Character'**
  String get themeColorCharacter;

  /// No description provided for @themeColorPositive.
  ///
  /// In en, this message translates to:
  /// **'Positive'**
  String get themeColorPositive;

  /// No description provided for @themeColorNegative.
  ///
  /// In en, this message translates to:
  /// **'Negative'**
  String get themeColorNegative;

  /// No description provided for @themeFont.
  ///
  /// In en, this message translates to:
  /// **'FONT'**
  String get themeFont;

  /// No description provided for @themeTextScale.
  ///
  /// In en, this message translates to:
  /// **'TEXT SCALE'**
  String get themeTextScale;

  /// No description provided for @themeHeaderScale.
  ///
  /// In en, this message translates to:
  /// **'HEADER SCALE'**
  String get themeHeaderScale;

  /// No description provided for @themeTitleScale.
  ///
  /// In en, this message translates to:
  /// **'TITLE SCALE'**
  String get themeTitleScale;

  /// No description provided for @themeButtonScale.
  ///
  /// In en, this message translates to:
  /// **'BUTTON SCALE'**
  String get themeButtonScale;

  /// No description provided for @themeSmall.
  ///
  /// In en, this message translates to:
  /// **'SMALL'**
  String get themeSmall;

  /// No description provided for @themeLarge.
  ///
  /// In en, this message translates to:
  /// **'LARGE'**
  String get themeLarge;

  /// No description provided for @themePromptInput.
  ///
  /// In en, this message translates to:
  /// **'PROMPT INPUT'**
  String get themePromptInput;

  /// No description provided for @themeFontSize.
  ///
  /// In en, this message translates to:
  /// **'FONT SIZE'**
  String get themeFontSize;

  /// No description provided for @themeHeightLabel.
  ///
  /// In en, this message translates to:
  /// **'HEIGHT'**
  String get themeHeightLabel;

  /// No description provided for @themeLines.
  ///
  /// In en, this message translates to:
  /// **'{count} lines'**
  String themeLines(int count);

  /// No description provided for @themeBrightMode.
  ///
  /// In en, this message translates to:
  /// **'BRIGHT MODE'**
  String get themeBrightMode;

  /// No description provided for @themeBrightText.
  ///
  /// In en, this message translates to:
  /// **'BRIGHT TEXT'**
  String get themeBrightText;

  /// No description provided for @themeBrightDesc.
  ///
  /// In en, this message translates to:
  /// **'Use brighter text colors for improved readability'**
  String get themeBrightDesc;

  /// No description provided for @themePanelLayout.
  ///
  /// In en, this message translates to:
  /// **'PANEL LAYOUT'**
  String get themePanelLayout;

  /// No description provided for @themePanelLayoutDesc.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder Advanced Settings sections'**
  String get themePanelLayoutDesc;

  /// No description provided for @themeDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'DELETE THEME'**
  String get themeDeleteTitle;

  /// No description provided for @themeDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'ARE YOU SURE YOU WANT TO DELETE \'\'{name}\'\'?'**
  String themeDeleteConfirm(String name);

  /// No description provided for @themeNewTitle.
  ///
  /// In en, this message translates to:
  /// **'NEW THEME'**
  String get themeNewTitle;

  /// No description provided for @themeCustomTheme.
  ///
  /// In en, this message translates to:
  /// **'Custom Theme'**
  String get themeCustomTheme;

  /// No description provided for @themeThemeName.
  ///
  /// In en, this message translates to:
  /// **'THEME NAME'**
  String get themeThemeName;

  /// No description provided for @themeCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create theme: {error}'**
  String themeCreateFailed(String error);

  /// No description provided for @themeSectionDimSeed.
  ///
  /// In en, this message translates to:
  /// **'DIMENSIONS + SEED'**
  String get themeSectionDimSeed;

  /// No description provided for @themeSectionStepsScale.
  ///
  /// In en, this message translates to:
  /// **'STEPS + SCALE'**
  String get themeSectionStepsScale;

  /// No description provided for @themeSectionSamplerPost.
  ///
  /// In en, this message translates to:
  /// **'SAMPLER + POST-PROCESSING'**
  String get themeSectionSamplerPost;

  /// No description provided for @themeSectionStyles.
  ///
  /// In en, this message translates to:
  /// **'STYLES'**
  String get themeSectionStyles;

  /// No description provided for @themeSectionNegPrompt.
  ///
  /// In en, this message translates to:
  /// **'NEGATIVE PROMPT'**
  String get themeSectionNegPrompt;

  /// No description provided for @themeSectionPresets.
  ///
  /// In en, this message translates to:
  /// **'PRESETS'**
  String get themeSectionPresets;

  /// No description provided for @themeSectionSaveAlbum.
  ///
  /// In en, this message translates to:
  /// **'SAVE TO ALBUM'**
  String get themeSectionSaveAlbum;

  /// No description provided for @themePreviewHeader.
  ///
  /// In en, this message translates to:
  /// **'HEADER TEXT'**
  String get themePreviewHeader;

  /// No description provided for @themePreviewSecondary.
  ///
  /// In en, this message translates to:
  /// **'Secondary text content'**
  String get themePreviewSecondary;

  /// No description provided for @themePreviewHint.
  ///
  /// In en, this message translates to:
  /// **'Hint / tertiary text'**
  String get themePreviewHint;

  /// No description provided for @themePreviewGenerate.
  ///
  /// In en, this message translates to:
  /// **'GENERATE'**
  String get themePreviewGenerate;

  /// No description provided for @themePreviewEdit.
  ///
  /// In en, this message translates to:
  /// **'EDIT'**
  String get themePreviewEdit;

  /// No description provided for @cascadeEditorLabel.
  ///
  /// In en, this message translates to:
  /// **'CASCADE EDITOR'**
  String get cascadeEditorLabel;

  /// No description provided for @cascadeSavedToLibrary.
  ///
  /// In en, this message translates to:
  /// **'CASCADE SAVED TO LIBRARY'**
  String get cascadeSavedToLibrary;

  /// No description provided for @cascadeNoBeatSelected.
  ///
  /// In en, this message translates to:
  /// **'NO BEAT SELECTED'**
  String get cascadeNoBeatSelected;

  /// No description provided for @cascadeScenePrompt.
  ///
  /// In en, this message translates to:
  /// **'SCENE / ACTION'**
  String get cascadeScenePrompt;

  /// No description provided for @cascadeSceneSubLabel.
  ///
  /// In en, this message translates to:
  /// **'what\'s happening + framing'**
  String get cascadeSceneSubLabel;

  /// No description provided for @cascadeSceneHint.
  ///
  /// In en, this message translates to:
  /// **'what\'s happening: e.g. 2girls, hugging, wide shot, from above'**
  String get cascadeSceneHint;

  /// No description provided for @cascadeEnvironmentPrompt.
  ///
  /// In en, this message translates to:
  /// **'ENVIRONMENT PROMPT'**
  String get cascadeEnvironmentPrompt;

  /// No description provided for @cascadeEnvSubLabel.
  ///
  /// In en, this message translates to:
  /// **'where it takes place'**
  String get cascadeEnvSubLabel;

  /// No description provided for @cascadeEnvHint.
  ///
  /// In en, this message translates to:
  /// **'where: e.g. forest, night, indoors, cinematic lighting'**
  String get cascadeEnvHint;

  /// No description provided for @cascadeApplyToAll.
  ///
  /// In en, this message translates to:
  /// **'Apply to all'**
  String get cascadeApplyToAll;

  /// No description provided for @cascadeSceneApplied.
  ///
  /// In en, this message translates to:
  /// **'SCENE APPLIED TO ALL BEATS'**
  String get cascadeSceneApplied;

  /// No description provided for @cascadeCharacterSlots.
  ///
  /// In en, this message translates to:
  /// **'CHARACTER SLOTS'**
  String get cascadeCharacterSlots;

  /// No description provided for @cascadeCharacterSlotN.
  ///
  /// In en, this message translates to:
  /// **'CHARACTER SLOT {n}'**
  String cascadeCharacterSlotN(int n);

  /// No description provided for @cascadePosition.
  ///
  /// In en, this message translates to:
  /// **'POSITION'**
  String get cascadePosition;

  /// No description provided for @cascadeAiPosition.
  ///
  /// In en, this message translates to:
  /// **'AI POSITION'**
  String get cascadeAiPosition;

  /// No description provided for @cascadePositivePrompt.
  ///
  /// In en, this message translates to:
  /// **'POSITIVE PROMPT'**
  String get cascadePositivePrompt;

  /// No description provided for @cascadeCharHint.
  ///
  /// In en, this message translates to:
  /// **'Character tags, appearance, state...'**
  String get cascadeCharHint;

  /// No description provided for @cascadeNegativePrompt.
  ///
  /// In en, this message translates to:
  /// **'NEGATIVE PROMPT'**
  String get cascadeNegativePrompt;

  /// No description provided for @cascadeAvoidHint.
  ///
  /// In en, this message translates to:
  /// **'Avoid tags...'**
  String get cascadeAvoidHint;

  /// No description provided for @cascadeLinkAction.
  ///
  /// In en, this message translates to:
  /// **'Link Action'**
  String get cascadeLinkAction;

  /// No description provided for @cascadeBeatSettings.
  ///
  /// In en, this message translates to:
  /// **'BEAT SETTINGS'**
  String get cascadeBeatSettings;

  /// No description provided for @cascadeResolution.
  ///
  /// In en, this message translates to:
  /// **'RESOLUTION'**
  String get cascadeResolution;

  /// No description provided for @cascadeSampler.
  ///
  /// In en, this message translates to:
  /// **'SAMPLER'**
  String get cascadeSampler;

  /// No description provided for @cascadeSteps.
  ///
  /// In en, this message translates to:
  /// **'STEPS'**
  String get cascadeSteps;

  /// No description provided for @cascadeScale.
  ///
  /// In en, this message translates to:
  /// **'SCALE'**
  String get cascadeScale;

  /// No description provided for @cascadeStyles.
  ///
  /// In en, this message translates to:
  /// **'STYLES'**
  String get cascadeStyles;

  /// No description provided for @cascadeNoStyles.
  ///
  /// In en, this message translates to:
  /// **'NO STYLES AVAILABLE'**
  String get cascadeNoStyles;

  /// No description provided for @cascadeLibrary.
  ///
  /// In en, this message translates to:
  /// **'CASCADE LIBRARY'**
  String get cascadeLibrary;

  /// No description provided for @cascadeSequencesSaved.
  ///
  /// In en, this message translates to:
  /// **'{count} SEQUENCES SAVED'**
  String cascadeSequencesSaved(int count);

  /// No description provided for @cascadeNew.
  ///
  /// In en, this message translates to:
  /// **'NEW CASCADE'**
  String get cascadeNew;

  /// No description provided for @cascadeNoCascades.
  ///
  /// In en, this message translates to:
  /// **'NO CASCADES FOUND'**
  String get cascadeNoCascades;

  /// No description provided for @cascadeBeatsAndSlots.
  ///
  /// In en, this message translates to:
  /// **'{beats} BEATS • {slots} CHARACTER SLOTS'**
  String cascadeBeatsAndSlots(int beats, int slots);

  /// No description provided for @cascadeCreateNew.
  ///
  /// In en, this message translates to:
  /// **'CREATE NEW CASCADE'**
  String get cascadeCreateNew;

  /// No description provided for @cascadeName.
  ///
  /// In en, this message translates to:
  /// **'CASCADE NAME'**
  String get cascadeName;

  /// No description provided for @cascadeCharSlotsLabel.
  ///
  /// In en, this message translates to:
  /// **'CHARACTER SLOTS'**
  String get cascadeCharSlotsLabel;

  /// No description provided for @cascadeAutoPosition.
  ///
  /// In en, this message translates to:
  /// **'AUTO POSITION (LET AI DECIDE)'**
  String get cascadeAutoPosition;

  /// No description provided for @cascadeDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'DELETE CASCADE?'**
  String get cascadeDeleteTitle;

  /// No description provided for @cascadeDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String cascadeDeleteConfirm(String name);

  /// No description provided for @cascadeSelect.
  ///
  /// In en, this message translates to:
  /// **'SELECT CASCADE'**
  String get cascadeSelect;

  /// No description provided for @cascadeNoSaved.
  ///
  /// In en, this message translates to:
  /// **'NO SAVED CASCADES FOUND'**
  String get cascadeNoSaved;

  /// No description provided for @cascadeCharactersAndBeats.
  ///
  /// In en, this message translates to:
  /// **'{chars} CHARACTERS • {beats} BEATS'**
  String cascadeCharactersAndBeats(int chars, int beats);

  /// No description provided for @cascadeCharTags.
  ///
  /// In en, this message translates to:
  /// **'CHAR {n} TAGS'**
  String cascadeCharTags(int n);

  /// No description provided for @cascadeGlobalScene.
  ///
  /// In en, this message translates to:
  /// **'GLOBAL SCENE (tags for every beat)'**
  String get cascadeGlobalScene;

  /// No description provided for @cascadeGlobalStyle.
  ///
  /// In en, this message translates to:
  /// **'GLOBAL STYLE / INJECTION'**
  String get cascadeGlobalStyle;

  /// No description provided for @cascadeCaptionHint.
  ///
  /// In en, this message translates to:
  /// **'Narrate this beat... (shown over the preview)'**
  String get cascadeCaptionHint;

  /// No description provided for @cascadeCaptionToggle.
  ///
  /// In en, this message translates to:
  /// **'Show / hide captions'**
  String get cascadeCaptionToggle;

  /// No description provided for @cascadeExportTooltip.
  ///
  /// In en, this message translates to:
  /// **'Export with captions'**
  String get cascadeExportTooltip;

  /// No description provided for @cascadeExportBeat.
  ///
  /// In en, this message translates to:
  /// **'Export this beat (caption burned in)'**
  String get cascadeExportBeat;

  /// No description provided for @cascadeExportStripVertical.
  ///
  /// In en, this message translates to:
  /// **'Storyboard strip — vertical'**
  String get cascadeExportStripVertical;

  /// No description provided for @cascadeExportStripHorizontal.
  ///
  /// In en, this message translates to:
  /// **'Storyboard strip — horizontal'**
  String get cascadeExportStripHorizontal;

  /// No description provided for @cascadeExportSaved.
  ///
  /// In en, this message translates to:
  /// **'EXPORTED'**
  String get cascadeExportSaved;

  /// No description provided for @cascadeExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get cascadeExportFailed;

  /// No description provided for @cascadeStripDownscaled.
  ///
  /// In en, this message translates to:
  /// **'Storyboard shrunk to fit memory limits'**
  String get cascadeStripDownscaled;

  /// No description provided for @cascadeRegenerateBeat.
  ///
  /// In en, this message translates to:
  /// **'REGENERATE BEAT {n}'**
  String cascadeRegenerateBeat(int n);

  /// No description provided for @cascadeGenerateBeat.
  ///
  /// In en, this message translates to:
  /// **'GENERATE BEAT {n}'**
  String cascadeGenerateBeat(int n);

  /// No description provided for @cascadeSkipToNext.
  ///
  /// In en, this message translates to:
  /// **'Skip to next'**
  String get cascadeSkipToNext;

  /// No description provided for @cascadeBeatRenderError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t build this beat. Check character appearances are set.'**
  String get cascadeBeatRenderError;

  /// No description provided for @cascadeStartCasting.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get cascadeStartCasting;

  /// No description provided for @cascadeBackToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get cascadeBackToLibrary;

  /// No description provided for @cascadeUnsavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved Changes'**
  String get cascadeUnsavedTitle;

  /// No description provided for @cascadeUnsavedMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes to this cascade. Discard them?'**
  String get cascadeUnsavedMessage;

  /// No description provided for @cascadeDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get cascadeDiscard;

  /// No description provided for @cascadeExitCascade.
  ///
  /// In en, this message translates to:
  /// **'Exit Cascade'**
  String get cascadeExitCascade;

  /// No description provided for @img2imgResult.
  ///
  /// In en, this message translates to:
  /// **'RESULT'**
  String get img2imgResult;

  /// No description provided for @img2imgSource.
  ///
  /// In en, this message translates to:
  /// **'SOURCE'**
  String get img2imgSource;

  /// No description provided for @img2imgCanvas.
  ///
  /// In en, this message translates to:
  /// **'CANVAS'**
  String get img2imgCanvas;

  /// No description provided for @img2imgUseAsSource.
  ///
  /// In en, this message translates to:
  /// **'USE AS SOURCE'**
  String get img2imgUseAsSource;

  /// No description provided for @img2imgBackToPicker.
  ///
  /// In en, this message translates to:
  /// **'Back to picker'**
  String get img2imgBackToPicker;

  /// No description provided for @img2imgGenerating.
  ///
  /// In en, this message translates to:
  /// **'GENERATING...'**
  String get img2imgGenerating;

  /// No description provided for @img2imgGenerate.
  ///
  /// In en, this message translates to:
  /// **'GENERATE'**
  String get img2imgGenerate;

  /// No description provided for @img2imgGenerationFailed.
  ///
  /// In en, this message translates to:
  /// **'Generation failed: {error}'**
  String img2imgGenerationFailed(String error);

  /// No description provided for @img2imgSettings.
  ///
  /// In en, this message translates to:
  /// **'IMG2IMG SETTINGS'**
  String get img2imgSettings;

  /// No description provided for @img2imgPrompt.
  ///
  /// In en, this message translates to:
  /// **'PROMPT'**
  String get img2imgPrompt;

  /// No description provided for @img2imgPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Describe what to generate...'**
  String get img2imgPromptHint;

  /// No description provided for @img2imgNegative.
  ///
  /// In en, this message translates to:
  /// **'NEGATIVE'**
  String get img2imgNegative;

  /// No description provided for @img2imgNegativeHint.
  ///
  /// In en, this message translates to:
  /// **'Undesired content...'**
  String get img2imgNegativeHint;

  /// No description provided for @img2imgStrength.
  ///
  /// In en, this message translates to:
  /// **'STRENGTH'**
  String get img2imgStrength;

  /// No description provided for @img2imgNoise.
  ///
  /// In en, this message translates to:
  /// **'NOISE'**
  String get img2imgNoise;

  /// No description provided for @img2imgMaskBlur.
  ///
  /// In en, this message translates to:
  /// **'MASK BLUR'**
  String get img2imgMaskBlur;

  /// No description provided for @img2imgColorCorrect.
  ///
  /// In en, this message translates to:
  /// **'COLOR CORRECT'**
  String get img2imgColorCorrect;

  /// No description provided for @img2imgSourceInfo.
  ///
  /// In en, this message translates to:
  /// **'SOURCE'**
  String get img2imgSourceInfo;

  /// No description provided for @img2imgMaskStrokes.
  ///
  /// In en, this message translates to:
  /// **'MASK: {count} strokes'**
  String img2imgMaskStrokes(int count);

  /// No description provided for @img2imgClearMaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear mask?'**
  String get img2imgClearMaskTitle;

  /// No description provided for @img2imgClearMaskMessage.
  ///
  /// In en, this message translates to:
  /// **'All mask strokes will be removed. This cannot be undone.'**
  String get img2imgClearMaskMessage;

  /// No description provided for @img2imgClearMaskConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get img2imgClearMaskConfirm;

  /// No description provided for @img2imgMaskUndoStroke.
  ///
  /// In en, this message translates to:
  /// **'Undo stroke'**
  String get img2imgMaskUndoStroke;

  /// No description provided for @img2imgMaskClearTooltip.
  ///
  /// In en, this message translates to:
  /// **'Clear mask'**
  String get img2imgMaskClearTooltip;

  /// No description provided for @img2imgBrushRound.
  ///
  /// In en, this message translates to:
  /// **'Round brush'**
  String get img2imgBrushRound;

  /// No description provided for @img2imgBrushSquare.
  ///
  /// In en, this message translates to:
  /// **'Square brush'**
  String get img2imgBrushSquare;

  /// No description provided for @img2imgBrushSize.
  ///
  /// In en, this message translates to:
  /// **'SIZE'**
  String get img2imgBrushSize;

  /// No description provided for @img2imgMaskDisplay.
  ///
  /// In en, this message translates to:
  /// **'Mask display settings'**
  String get img2imgMaskDisplay;

  /// No description provided for @img2imgMaskSave.
  ///
  /// In en, this message translates to:
  /// **'Save mask'**
  String get img2imgMaskSave;

  /// No description provided for @img2imgMaskLoad.
  ///
  /// In en, this message translates to:
  /// **'Load mask'**
  String get img2imgMaskLoad;

  /// No description provided for @img2imgMaskSaved.
  ///
  /// In en, this message translates to:
  /// **'Mask saved'**
  String get img2imgMaskSaved;

  /// No description provided for @img2imgMaskColor.
  ///
  /// In en, this message translates to:
  /// **'COLOR'**
  String get img2imgMaskColor;

  /// No description provided for @img2imgMaskOpacity.
  ///
  /// In en, this message translates to:
  /// **'OPACITY'**
  String get img2imgMaskOpacity;

  /// No description provided for @img2imgMaskPatternSolid.
  ///
  /// In en, this message translates to:
  /// **'Solid'**
  String get img2imgMaskPatternSolid;

  /// No description provided for @img2imgMaskPatternStripe.
  ///
  /// In en, this message translates to:
  /// **'Stripe'**
  String get img2imgMaskPatternStripe;

  /// No description provided for @img2imgMaskPatternCross.
  ///
  /// In en, this message translates to:
  /// **'Cross'**
  String get img2imgMaskPatternCross;

  /// No description provided for @img2imgMaskBorder.
  ///
  /// In en, this message translates to:
  /// **'BORDER'**
  String get img2imgMaskBorder;

  /// No description provided for @img2imgMaskBorderTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show mask border'**
  String get img2imgMaskBorderTooltip;

  /// No description provided for @img2imgNoMask.
  ///
  /// In en, this message translates to:
  /// **'NO MASK (full img2img)'**
  String get img2imgNoMask;

  /// No description provided for @img2imgImportPrompt.
  ///
  /// In en, this message translates to:
  /// **'Import Prompt'**
  String get img2imgImportPrompt;

  /// No description provided for @img2imgImportPromptDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-fill prompt from source image metadata'**
  String get img2imgImportPromptDesc;

  /// No description provided for @img2imgUploadFromDevice.
  ///
  /// In en, this message translates to:
  /// **'UPLOAD FROM DEVICE'**
  String get img2imgUploadFromDevice;

  /// No description provided for @img2imgUploadFromDeviceDesc.
  ///
  /// In en, this message translates to:
  /// **'Pick an image from your photo library or files'**
  String get img2imgUploadFromDeviceDesc;

  /// No description provided for @img2imgBlankCanvas.
  ///
  /// In en, this message translates to:
  /// **'BLANK CANVAS'**
  String get img2imgBlankCanvas;

  /// No description provided for @img2imgBlankCanvasDesc.
  ///
  /// In en, this message translates to:
  /// **'Create a blank image to draw on'**
  String get img2imgBlankCanvasDesc;

  /// No description provided for @img2imgBlankCanvasSize.
  ///
  /// In en, this message translates to:
  /// **'CANVAS SIZE'**
  String get img2imgBlankCanvasSize;

  /// No description provided for @img2imgPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'SELECT SOURCE IMAGE'**
  String get img2imgPickerTitle;

  /// No description provided for @img2imgPickerDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose an image to use as the base for img2img or inpainting'**
  String get img2imgPickerDesc;

  /// No description provided for @img2imgUseCurrent.
  ///
  /// In en, this message translates to:
  /// **'USE CURRENT GENERATION'**
  String get img2imgUseCurrent;

  /// No description provided for @img2imgUseCurrentDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the last generated image as source'**
  String get img2imgUseCurrentDesc;

  /// No description provided for @slideshowTitle.
  ///
  /// In en, this message translates to:
  /// **'SLIDESHOW'**
  String get slideshowTitle;

  /// No description provided for @slideshowPlayAll.
  ///
  /// In en, this message translates to:
  /// **'PLAY ALL'**
  String get slideshowPlayAll;

  /// No description provided for @slideshowPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous image'**
  String get slideshowPrevious;

  /// No description provided for @slideshowNext.
  ///
  /// In en, this message translates to:
  /// **'Next image'**
  String get slideshowNext;

  /// No description provided for @slideshowPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get slideshowPause;

  /// No description provided for @slideshowResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get slideshowResume;

  /// No description provided for @slideshowMusic.
  ///
  /// In en, this message translates to:
  /// **'MUSIC'**
  String get slideshowMusic;

  /// No description provided for @slideshowEnableMusic.
  ///
  /// In en, this message translates to:
  /// **'ENABLE MUSIC'**
  String get slideshowEnableMusic;

  /// No description provided for @slideshowMusicVolume.
  ///
  /// In en, this message translates to:
  /// **'MUSIC VOLUME'**
  String get slideshowMusicVolume;

  /// No description provided for @slideshowKaraoke.
  ///
  /// In en, this message translates to:
  /// **'KARAOKE LYRICS'**
  String get slideshowKaraoke;

  /// No description provided for @slideshowSongsHint.
  ///
  /// In en, this message translates to:
  /// **'SONGS (TAP TO SELECT, EMPTY = ALL)'**
  String get slideshowSongsHint;

  /// No description provided for @slideshowSoundFont.
  ///
  /// In en, this message translates to:
  /// **'SOUNDFONT'**
  String get slideshowSoundFont;

  /// No description provided for @slideshowSoundFontDefault.
  ///
  /// In en, this message translates to:
  /// **'DEFAULT'**
  String get slideshowSoundFontDefault;

  /// No description provided for @slideshowCategoryAll.
  ///
  /// In en, this message translates to:
  /// **'ALL'**
  String get slideshowCategoryAll;

  /// No description provided for @slideshowConfigs.
  ///
  /// In en, this message translates to:
  /// **'CONFIGS'**
  String get slideshowConfigs;

  /// No description provided for @slideshowNewConfig.
  ///
  /// In en, this message translates to:
  /// **'NEW CONFIG'**
  String get slideshowNewConfig;

  /// No description provided for @slideshowNoConfigs.
  ///
  /// In en, this message translates to:
  /// **'NO SLIDESHOW CONFIGS YET.\nTAP + TO CREATE ONE.'**
  String get slideshowNoConfigs;

  /// No description provided for @slideshowSelectOrCreate.
  ///
  /// In en, this message translates to:
  /// **'SELECT OR CREATE A SLIDESHOW CONFIG'**
  String get slideshowSelectOrCreate;

  /// No description provided for @slideshowNameLabel.
  ///
  /// In en, this message translates to:
  /// **'NAME'**
  String get slideshowNameLabel;

  /// No description provided for @slideshowSourceLabel.
  ///
  /// In en, this message translates to:
  /// **'SOURCE'**
  String get slideshowSourceLabel;

  /// No description provided for @slideshowTransition.
  ///
  /// In en, this message translates to:
  /// **'TRANSITION'**
  String get slideshowTransition;

  /// No description provided for @slideshowTransitionDuration.
  ///
  /// In en, this message translates to:
  /// **'TRANSITION DURATION'**
  String get slideshowTransitionDuration;

  /// No description provided for @slideshowTiming.
  ///
  /// In en, this message translates to:
  /// **'TIMING'**
  String get slideshowTiming;

  /// No description provided for @slideshowSlideDuration.
  ///
  /// In en, this message translates to:
  /// **'SLIDE DURATION'**
  String get slideshowSlideDuration;

  /// No description provided for @slideshowKenBurns.
  ///
  /// In en, this message translates to:
  /// **'KEN BURNS EFFECT'**
  String get slideshowKenBurns;

  /// No description provided for @slideshowEnabled.
  ///
  /// In en, this message translates to:
  /// **'ENABLED'**
  String get slideshowEnabled;

  /// No description provided for @slideshowIntensity.
  ///
  /// In en, this message translates to:
  /// **'INTENSITY'**
  String get slideshowIntensity;

  /// No description provided for @slideshowManualZoom.
  ///
  /// In en, this message translates to:
  /// **'MANUAL ZOOM'**
  String get slideshowManualZoom;

  /// No description provided for @slideshowPlayback.
  ///
  /// In en, this message translates to:
  /// **'PLAYBACK'**
  String get slideshowPlayback;

  /// No description provided for @slideshowShuffle.
  ///
  /// In en, this message translates to:
  /// **'SHUFFLE'**
  String get slideshowShuffle;

  /// No description provided for @slideshowLoop.
  ///
  /// In en, this message translates to:
  /// **'LOOP'**
  String get slideshowLoop;

  /// No description provided for @slideshowDefault.
  ///
  /// In en, this message translates to:
  /// **'DEFAULT'**
  String get slideshowDefault;

  /// No description provided for @slideshowUseAsDefault.
  ///
  /// In en, this message translates to:
  /// **'USE AS DEFAULT SLIDESHOW'**
  String get slideshowUseAsDefault;

  /// No description provided for @slideshowPlay.
  ///
  /// In en, this message translates to:
  /// **'PLAY SLIDESHOW'**
  String get slideshowPlay;

  /// No description provided for @slideshowTransFade.
  ///
  /// In en, this message translates to:
  /// **'FADE'**
  String get slideshowTransFade;

  /// No description provided for @slideshowTransSlideL.
  ///
  /// In en, this message translates to:
  /// **'SLIDE L'**
  String get slideshowTransSlideL;

  /// No description provided for @slideshowTransSlideR.
  ///
  /// In en, this message translates to:
  /// **'SLIDE R'**
  String get slideshowTransSlideR;

  /// No description provided for @slideshowTransSlideUp.
  ///
  /// In en, this message translates to:
  /// **'SLIDE UP'**
  String get slideshowTransSlideUp;

  /// No description provided for @slideshowTransZoom.
  ///
  /// In en, this message translates to:
  /// **'ZOOM'**
  String get slideshowTransZoom;

  /// No description provided for @slideshowTransXZoom.
  ///
  /// In en, this message translates to:
  /// **'X-ZOOM'**
  String get slideshowTransXZoom;

  /// No description provided for @slideshowSourceAllImages.
  ///
  /// In en, this message translates to:
  /// **'ALL IMAGES'**
  String get slideshowSourceAllImages;

  /// No description provided for @slideshowSourceAlbum.
  ///
  /// In en, this message translates to:
  /// **'ALBUM'**
  String get slideshowSourceAlbum;

  /// No description provided for @slideshowSourceFavorites.
  ///
  /// In en, this message translates to:
  /// **'FAVORITES'**
  String get slideshowSourceFavorites;

  /// No description provided for @slideshowSourceCustom.
  ///
  /// In en, this message translates to:
  /// **'{count} CUSTOM'**
  String slideshowSourceCustom(int count);

  /// No description provided for @slideshowDeleteConfig.
  ///
  /// In en, this message translates to:
  /// **'DELETE CONFIG'**
  String get slideshowDeleteConfig;

  /// No description provided for @slideshowDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'DELETE \'\'{name}\'\'?'**
  String slideshowDeleteConfirm(String name);

  /// No description provided for @slideshowImageSource.
  ///
  /// In en, this message translates to:
  /// **'IMAGE SOURCE'**
  String get slideshowImageSource;

  /// No description provided for @slideshowAllImages.
  ///
  /// In en, this message translates to:
  /// **'ALL IMAGES'**
  String get slideshowAllImages;

  /// No description provided for @slideshowImageCount.
  ///
  /// In en, this message translates to:
  /// **'{count} images'**
  String slideshowImageCount(int count);

  /// No description provided for @slideshowFavoritesLabel.
  ///
  /// In en, this message translates to:
  /// **'FAVORITES'**
  String get slideshowFavoritesLabel;

  /// No description provided for @slideshowAlbumLabel.
  ///
  /// In en, this message translates to:
  /// **'ALBUM'**
  String get slideshowAlbumLabel;

  /// No description provided for @slideshowCustomSelection.
  ///
  /// In en, this message translates to:
  /// **'CUSTOM SELECTION'**
  String get slideshowCustomSelection;

  /// No description provided for @slideshowSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String slideshowSelectedCount(int count);

  /// No description provided for @slideshowNoAlbums.
  ///
  /// In en, this message translates to:
  /// **'NO ALBUMS CREATED'**
  String get slideshowNoAlbums;

  /// No description provided for @slideshowSelectAlbum.
  ///
  /// In en, this message translates to:
  /// **'SELECT ALBUM'**
  String get slideshowSelectAlbum;

  /// No description provided for @slideshowCustomCount.
  ///
  /// In en, this message translates to:
  /// **'{selected} / {total} SELECTED'**
  String slideshowCustomCount(int selected, int total);

  /// No description provided for @slideshowDeselectAll.
  ///
  /// In en, this message translates to:
  /// **'DESELECT ALL'**
  String get slideshowDeselectAll;

  /// No description provided for @slideshowSelectAll.
  ///
  /// In en, this message translates to:
  /// **'SELECT ALL'**
  String get slideshowSelectAll;

  /// No description provided for @slideshowNoImages.
  ///
  /// In en, this message translates to:
  /// **'NO IMAGES TO SHOW'**
  String get slideshowNoImages;

  /// No description provided for @slideshowGoBack.
  ///
  /// In en, this message translates to:
  /// **'GO BACK'**
  String get slideshowGoBack;

  /// No description provided for @demoImagesSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} IMAGES SELECTED'**
  String demoImagesSelected(int count);

  /// No description provided for @demoAll.
  ///
  /// In en, this message translates to:
  /// **'ALL'**
  String get demoAll;

  /// No description provided for @demoClear.
  ///
  /// In en, this message translates to:
  /// **'CLEAR'**
  String get demoClear;

  /// No description provided for @demoNoImages.
  ///
  /// In en, this message translates to:
  /// **'NO IMAGES IN GALLERY'**
  String get demoNoImages;

  /// No description provided for @demoGridSize.
  ///
  /// In en, this message translates to:
  /// **'Change grid size'**
  String get demoGridSize;

  /// No description provided for @cascadeBeatTimeline.
  ///
  /// In en, this message translates to:
  /// **'BEAT TIMELINE'**
  String get cascadeBeatTimeline;

  /// No description provided for @cascadeBeatsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} BEATS'**
  String cascadeBeatsCount(int count);

  /// No description provided for @cascadeBeatN.
  ///
  /// In en, this message translates to:
  /// **'BEAT {n}'**
  String cascadeBeatN(int n);

  /// No description provided for @cascadeCloneBeat.
  ///
  /// In en, this message translates to:
  /// **'Clone Beat'**
  String get cascadeCloneBeat;

  /// No description provided for @cascadeRemoveBeat.
  ///
  /// In en, this message translates to:
  /// **'Remove Beat'**
  String get cascadeRemoveBeat;

  /// No description provided for @cascadeRemoveBeatMessage.
  ///
  /// In en, this message translates to:
  /// **'This beat and its prompts will be removed from the sequence.'**
  String get cascadeRemoveBeatMessage;

  /// No description provided for @cascadeRemoveActionTag.
  ///
  /// In en, this message translates to:
  /// **'Remove action tag'**
  String get cascadeRemoveActionTag;

  /// No description provided for @settingsCheckForUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for Updates'**
  String get settingsCheckForUpdates;

  /// No description provided for @settingsUpdateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update Available'**
  String get settingsUpdateAvailable;

  /// No description provided for @settingsUpdateAvailableDesc.
  ///
  /// In en, this message translates to:
  /// **'A new version ({version}) is available.'**
  String settingsUpdateAvailableDesc(String version);

  /// No description provided for @settingsUpdateDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get settingsUpdateDownload;

  /// No description provided for @settingsUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You\'re up to date!'**
  String get settingsUpToDate;

  /// No description provided for @settingsUpdateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Update check failed'**
  String get settingsUpdateCheckFailed;

  /// No description provided for @settingsUpdateDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading update…'**
  String get settingsUpdateDownloading;

  /// No description provided for @settingsUpdateProgress.
  ///
  /// In en, this message translates to:
  /// **'{received} / {total}'**
  String settingsUpdateProgress(String received, String total);

  /// No description provided for @settingsUpdateInstalling.
  ///
  /// In en, this message translates to:
  /// **'Starting installer…'**
  String get settingsUpdateInstalling;

  /// No description provided for @settingsUpdateRestartPrompt.
  ///
  /// In en, this message translates to:
  /// **'NAIWeaver will close to apply the update, then reopen automatically.'**
  String get settingsUpdateRestartPrompt;

  /// No description provided for @settingsUpdateDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get settingsUpdateDownloadFailed;

  /// No description provided for @settingsUpdateInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start the installer'**
  String get settingsUpdateInstallFailed;

  /// No description provided for @settingsUpdateOpenInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in browser'**
  String get settingsUpdateOpenInBrowser;

  /// No description provided for @settingsUpdateApply.
  ///
  /// In en, this message translates to:
  /// **'Update & Restart'**
  String get settingsUpdateApply;

  /// No description provided for @mainAnlas.
  ///
  /// In en, this message translates to:
  /// **'Anlas'**
  String get mainAnlas;

  /// No description provided for @mainEstimatedCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Estimated'**
  String get mainEstimatedCostLabel;

  /// No description provided for @mainEstimatedCostTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pre-generation estimate; final charge is reconciled from NovelAI\'s actual balance delta'**
  String get mainEstimatedCostTooltip;

  /// No description provided for @mainEstimatedCostBase.
  ///
  /// In en, this message translates to:
  /// **'Base'**
  String get mainEstimatedCostBase;

  /// No description provided for @mainEstimatedCostReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get mainEstimatedCostReference;

  /// No description provided for @mainEstimatedCostVibe.
  ///
  /// In en, this message translates to:
  /// **'Vibe'**
  String get mainEstimatedCostVibe;

  /// No description provided for @mainEstimatedCostSerialImages.
  ///
  /// In en, this message translates to:
  /// **'Serial images'**
  String get mainEstimatedCostSerialImages;

  /// No description provided for @settingsAnlasTracker.
  ///
  /// In en, this message translates to:
  /// **'Anlas Tracker'**
  String get settingsAnlasTracker;

  /// No description provided for @settingsAnlasTrackerDesc.
  ///
  /// In en, this message translates to:
  /// **'Show your Anlas balance in the top bar'**
  String get settingsAnlasTrackerDesc;

  /// No description provided for @settingsCopyButton.
  ///
  /// In en, this message translates to:
  /// **'Copy to Clipboard'**
  String get settingsCopyButton;

  /// No description provided for @settingsCopyButtonDesc.
  ///
  /// In en, this message translates to:
  /// **'Show copy button on generated images'**
  String get settingsCopyButtonDesc;

  /// No description provided for @settingsHideTagValues.
  ///
  /// In en, this message translates to:
  /// **'Hide Tag Values'**
  String get settingsHideTagValues;

  /// No description provided for @settingsHideTagValuesDesc.
  ///
  /// In en, this message translates to:
  /// **'Hide tag count values in autocomplete suggestions'**
  String get settingsHideTagValuesDesc;

  /// No description provided for @settingsFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get settingsFontSize;

  /// No description provided for @settingsFontSizeDesc.
  ///
  /// In en, this message translates to:
  /// **'Scales all UI text. Default 100%.'**
  String get settingsFontSizeDesc;

  /// No description provided for @settingsOpenLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Open External Link'**
  String get settingsOpenLinkTitle;

  /// No description provided for @settingsOpenLinkBody.
  ///
  /// In en, this message translates to:
  /// **'You are about to leave NAIWeaver and open a new window:'**
  String get settingsOpenLinkBody;

  /// No description provided for @settingsOpenLinkConfirm.
  ///
  /// In en, this message translates to:
  /// **'Open Link'**
  String get settingsOpenLinkConfirm;

  /// No description provided for @canvasEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'CANVAS EDITOR'**
  String get canvasEditorTitle;

  /// No description provided for @canvasEditInCanvas.
  ///
  /// In en, this message translates to:
  /// **'CANVAS'**
  String get canvasEditInCanvas;

  /// No description provided for @canvasPaint.
  ///
  /// In en, this message translates to:
  /// **'PAINT'**
  String get canvasPaint;

  /// No description provided for @canvasErase.
  ///
  /// In en, this message translates to:
  /// **'ERASE'**
  String get canvasErase;

  /// No description provided for @canvasSize.
  ///
  /// In en, this message translates to:
  /// **'SIZE'**
  String get canvasSize;

  /// No description provided for @canvasOpacity.
  ///
  /// In en, this message translates to:
  /// **'OPACITY'**
  String get canvasOpacity;

  /// No description provided for @canvasUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get canvasUndo;

  /// No description provided for @canvasRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get canvasRedo;

  /// No description provided for @canvasFlatten.
  ///
  /// In en, this message translates to:
  /// **'FLATTEN'**
  String get canvasFlatten;

  /// No description provided for @canvasFlattenSend.
  ///
  /// In en, this message translates to:
  /// **'FLATTEN & SEND'**
  String get canvasFlattenSend;

  /// No description provided for @canvasBack.
  ///
  /// In en, this message translates to:
  /// **'Back to img2img'**
  String get canvasBack;

  /// No description provided for @canvasDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'DISCARD CHANGES?'**
  String get canvasDiscardTitle;

  /// No description provided for @canvasDiscardMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved paint strokes. Discard them?'**
  String get canvasDiscardMessage;

  /// No description provided for @canvasDiscard.
  ///
  /// In en, this message translates to:
  /// **'DISCARD'**
  String get canvasDiscard;

  /// No description provided for @canvasFlattenFailed.
  ///
  /// In en, this message translates to:
  /// **'Flatten failed: {error}'**
  String canvasFlattenFailed(String error);

  /// No description provided for @canvasColor.
  ///
  /// In en, this message translates to:
  /// **'COLOR'**
  String get canvasColor;

  /// No description provided for @canvasLayers.
  ///
  /// In en, this message translates to:
  /// **'LAYERS'**
  String get canvasLayers;

  /// No description provided for @canvasLayerAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Layer'**
  String get canvasLayerAdd;

  /// No description provided for @canvasLayerDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Layer'**
  String get canvasLayerDelete;

  /// No description provided for @canvasLayerDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Layer'**
  String get canvasLayerDuplicate;

  /// No description provided for @canvasLayerOpacity.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get canvasLayerOpacity;

  /// No description provided for @canvasLayerBlendMode.
  ///
  /// In en, this message translates to:
  /// **'Blend'**
  String get canvasLayerBlendMode;

  /// No description provided for @canvasLayerDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this layer? Strokes will be lost.'**
  String get canvasLayerDeleteConfirm;

  /// No description provided for @canvasLayerClear.
  ///
  /// In en, this message translates to:
  /// **'Clear Layer'**
  String get canvasLayerClear;

  /// No description provided for @canvasLayerClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear all strokes on this layer?'**
  String get canvasLayerClearConfirm;

  /// No description provided for @canvasLine.
  ///
  /// In en, this message translates to:
  /// **'LINE'**
  String get canvasLine;

  /// No description provided for @canvasRectangle.
  ///
  /// In en, this message translates to:
  /// **'RECT'**
  String get canvasRectangle;

  /// No description provided for @canvasCircle.
  ///
  /// In en, this message translates to:
  /// **'CIRCLE'**
  String get canvasCircle;

  /// No description provided for @canvasEyedropper.
  ///
  /// In en, this message translates to:
  /// **'PICK'**
  String get canvasEyedropper;

  /// No description provided for @canvasTransform.
  ///
  /// In en, this message translates to:
  /// **'MOVE'**
  String get canvasTransform;

  /// No description provided for @canvasImportImage.
  ///
  /// In en, this message translates to:
  /// **'Import Image'**
  String get canvasImportImage;

  /// No description provided for @canvasHelp.
  ///
  /// In en, this message translates to:
  /// **'CANVAS HELP'**
  String get canvasHelp;

  /// No description provided for @canvasSmooth.
  ///
  /// In en, this message translates to:
  /// **'SMOOTH'**
  String get canvasSmooth;

  /// No description provided for @canvasFill.
  ///
  /// In en, this message translates to:
  /// **'FILL'**
  String get canvasFill;

  /// No description provided for @canvasText.
  ///
  /// In en, this message translates to:
  /// **'TEXT'**
  String get canvasText;

  /// No description provided for @canvasTextHint.
  ///
  /// In en, this message translates to:
  /// **'Enter text...'**
  String get canvasTextHint;

  /// No description provided for @canvasTextSize.
  ///
  /// In en, this message translates to:
  /// **'SIZE'**
  String get canvasTextSize;

  /// No description provided for @canvasTextFont.
  ///
  /// In en, this message translates to:
  /// **'FONT'**
  String get canvasTextFont;

  /// No description provided for @canvasTextSpacing.
  ///
  /// In en, this message translates to:
  /// **'SPACING'**
  String get canvasTextSpacing;

  /// No description provided for @canvasTextDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get canvasTextDefault;

  /// No description provided for @canvasSelectTool.
  ///
  /// In en, this message translates to:
  /// **'SELECT'**
  String get canvasSelectTool;

  /// No description provided for @canvasLassoTool.
  ///
  /// In en, this message translates to:
  /// **'LASSO'**
  String get canvasLassoTool;

  /// No description provided for @canvasBlurTool.
  ///
  /// In en, this message translates to:
  /// **'BLUR'**
  String get canvasBlurTool;

  /// No description provided for @canvasCloneTool.
  ///
  /// In en, this message translates to:
  /// **'CLONE'**
  String get canvasCloneTool;

  /// No description provided for @canvasResize.
  ///
  /// In en, this message translates to:
  /// **'Resize canvas'**
  String get canvasResize;

  /// No description provided for @canvasApply.
  ///
  /// In en, this message translates to:
  /// **'APPLY'**
  String get canvasApply;

  /// No description provided for @canvasDeleteSelection.
  ///
  /// In en, this message translates to:
  /// **'Delete selection contents'**
  String get canvasDeleteSelection;

  /// No description provided for @canvasPaletteTapHint.
  ///
  /// In en, this message translates to:
  /// **'Tap: select  •  Hold: replace with current'**
  String get canvasPaletteTapHint;

  /// No description provided for @canvasPaletteHoldHint.
  ///
  /// In en, this message translates to:
  /// **'Hold to replace'**
  String get canvasPaletteHoldHint;

  /// No description provided for @settingsOutputFolder.
  ///
  /// In en, this message translates to:
  /// **'Output Folder'**
  String get settingsOutputFolder;

  /// No description provided for @settingsOutputFolderDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose where generated images are saved'**
  String get settingsOutputFolderDesc;

  /// No description provided for @settingsFilenamePattern.
  ///
  /// In en, this message translates to:
  /// **'Filename Pattern'**
  String get settingsFilenamePattern;

  /// No description provided for @settingsFilenamePatternDesc.
  ///
  /// In en, this message translates to:
  /// **'Custom name for saved images. Tokens: <prompt>, <seed>, <album:fallback>, <year>, <month>, <day>, <hours>, <minutes>, <seconds>, <date>, <time>, <digits:0000>. Leave empty for the NAI-style default.'**
  String get settingsFilenamePatternDesc;

  /// No description provided for @settingsSavePathPattern.
  ///
  /// In en, this message translates to:
  /// **'Save Subfolder Pattern'**
  String get settingsSavePathPattern;

  /// No description provided for @settingsSavePathPatternDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-create subfolders under the output folder, e.g. <year>/<month>/<day>. Same tokens. Leave empty for none.'**
  String get settingsSavePathPatternDesc;

  /// No description provided for @settingsPatternPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get settingsPatternPreview;

  /// No description provided for @settingsOutputFolderDefault.
  ///
  /// In en, this message translates to:
  /// **'Default (App Storage)'**
  String get settingsOutputFolderDefault;

  /// No description provided for @settingsOutputFolderBrowse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get settingsOutputFolderBrowse;

  /// No description provided for @settingsFolderUseDefault.
  ///
  /// In en, this message translates to:
  /// **'Use default folder'**
  String get settingsFolderUseDefault;

  /// No description provided for @settingsUseSdCard.
  ///
  /// In en, this message translates to:
  /// **'Use SD Card'**
  String get settingsUseSdCard;

  /// No description provided for @settingsSdDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Move output to SD card'**
  String get settingsSdDialogTitle;

  /// No description provided for @settingsSdUninstallWarning.
  ///
  /// In en, this message translates to:
  /// **'Images on the SD card live in the app\'s own folder (Android/data). Android DELETES that folder when the app is uninstalled — on this device and on the card. Export anything precious somewhere else first.'**
  String get settingsSdUninstallWarning;

  /// No description provided for @settingsSdExistingInfo.
  ///
  /// In en, this message translates to:
  /// **'{count} existing files ({size}) can be moved to the SD card.'**
  String settingsSdExistingInfo(int count, String size);

  /// No description provided for @settingsSdMoveButton.
  ///
  /// In en, this message translates to:
  /// **'Move existing files'**
  String get settingsSdMoveButton;

  /// No description provided for @settingsSdFreshButton.
  ///
  /// In en, this message translates to:
  /// **'Start fresh'**
  String get settingsSdFreshButton;

  /// No description provided for @settingsSdAlready.
  ///
  /// In en, this message translates to:
  /// **'The output folder is already on the SD card'**
  String get settingsSdAlready;

  /// No description provided for @settingsSdNotEnoughSpace.
  ///
  /// In en, this message translates to:
  /// **'Not enough space on the SD card: needs {needed}, {available} available'**
  String settingsSdNotEnoughSpace(String needed, String available);

  /// No description provided for @settingsSdMoving.
  ///
  /// In en, this message translates to:
  /// **'Moving files to the SD card… keep the app open.'**
  String get settingsSdMoving;

  /// No description provided for @settingsSdMoveDone.
  ///
  /// In en, this message translates to:
  /// **'{count} files moved to the SD card'**
  String settingsSdMoveDone(int count);

  /// No description provided for @settingsSdMoveFailed.
  ///
  /// In en, this message translates to:
  /// **'{count} files could not be moved — tap USE SD CARD to retry'**
  String settingsSdMoveFailed(int count);

  /// No description provided for @settingsSdMovePaused.
  ///
  /// In en, this message translates to:
  /// **'Move paused — {count} files remain. Tap USE SD CARD to resume.'**
  String settingsSdMovePaused(int count);

  /// No description provided for @settingsSdResumeTitle.
  ///
  /// In en, this message translates to:
  /// **'Resume moving to SD card'**
  String get settingsSdResumeTitle;

  /// No description provided for @settingsSdResumeBody.
  ///
  /// In en, this message translates to:
  /// **'{count} files from a previous move are still waiting. Resume now?'**
  String settingsSdResumeBody(int count);

  /// No description provided for @settingsSdResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get settingsSdResume;

  /// No description provided for @resCustomEntry.
  ///
  /// In en, this message translates to:
  /// **'Custom...'**
  String get resCustomEntry;

  /// No description provided for @resCustomDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom Resolution'**
  String get resCustomDialogTitle;

  /// No description provided for @resCustomWidth.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get resCustomWidth;

  /// No description provided for @resCustomHeight.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get resCustomHeight;

  /// No description provided for @resCustomName.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get resCustomName;

  /// No description provided for @resCustomUseOnce.
  ///
  /// In en, this message translates to:
  /// **'Use Once'**
  String get resCustomUseOnce;

  /// No description provided for @resCustomSaveAndUse.
  ///
  /// In en, this message translates to:
  /// **'Save & Use'**
  String get resCustomSaveAndUse;

  /// No description provided for @resCustomMustBeMultiple.
  ///
  /// In en, this message translates to:
  /// **'Must be a multiple of 64'**
  String get resCustomMustBeMultiple;

  /// No description provided for @resCustomOutOfRange.
  ///
  /// In en, this message translates to:
  /// **'Must be between 64 and 2048'**
  String get resCustomOutOfRange;

  /// No description provided for @themeSectionCharacters.
  ///
  /// In en, this message translates to:
  /// **'CHARACTERS'**
  String get themeSectionCharacters;

  /// No description provided for @charEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get charEditorTitle;

  /// No description provided for @charEditorExpanded.
  ///
  /// In en, this message translates to:
  /// **'EXPANDED'**
  String get charEditorExpanded;

  /// No description provided for @charEditorCompact.
  ///
  /// In en, this message translates to:
  /// **'COMPACT'**
  String get charEditorCompact;

  /// No description provided for @charEditorAutoPosition.
  ///
  /// In en, this message translates to:
  /// **'AUTO'**
  String get charEditorAutoPosition;

  /// No description provided for @charEditorUsingCompactShelf.
  ///
  /// In en, this message translates to:
  /// **'Using compact shelf below prompt'**
  String get charEditorUsingCompactShelf;

  /// No description provided for @charEditorCharacterName.
  ///
  /// In en, this message translates to:
  /// **'CHARACTER NAME'**
  String get charEditorCharacterName;

  /// No description provided for @charEditorPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Character tags, appearance...'**
  String get charEditorPromptHint;

  /// No description provided for @charEditorUcHint.
  ///
  /// In en, this message translates to:
  /// **'Undesired tags...'**
  String get charEditorUcHint;

  /// No description provided for @charEditorShowUc.
  ///
  /// In en, this message translates to:
  /// **'UC'**
  String get charEditorShowUc;

  /// No description provided for @charEditorShowPosition.
  ///
  /// In en, this message translates to:
  /// **'POS'**
  String get charEditorShowPosition;

  /// No description provided for @charEditorShowPresets.
  ///
  /// In en, this message translates to:
  /// **'PRESET'**
  String get charEditorShowPresets;

  /// No description provided for @charEditorShowTitle.
  ///
  /// In en, this message translates to:
  /// **'TITLE'**
  String get charEditorShowTitle;

  /// No description provided for @charEditorAiDecidesPosition.
  ///
  /// In en, this message translates to:
  /// **'AI decides position'**
  String get charEditorAiDecidesPosition;

  /// No description provided for @charEditorAddCharacter.
  ///
  /// In en, this message translates to:
  /// **'ADD CHARACTER'**
  String get charEditorAddCharacter;

  /// No description provided for @charEditorCharacterLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Character limit reached (6)'**
  String get charEditorCharacterLimitReached;

  /// No description provided for @charEditorDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String charEditorDeleteConfirm(String name);

  /// No description provided for @charEditorDeleteCharacter.
  ///
  /// In en, this message translates to:
  /// **'DELETE CHARACTER'**
  String get charEditorDeleteCharacter;

  /// No description provided for @charEditorInteractions.
  ///
  /// In en, this message translates to:
  /// **'INTERACTIONS'**
  String get charEditorInteractions;

  /// No description provided for @charEditorAddInteraction.
  ///
  /// In en, this message translates to:
  /// **'ADD INTERACTION'**
  String get charEditorAddInteraction;

  /// No description provided for @charEditorInteractionDisplay.
  ///
  /// In en, this message translates to:
  /// **'{source} → {target}: {action}'**
  String charEditorInteractionDisplay(
    String source,
    String target,
    String action,
  );

  /// No description provided for @charEditorSavePreset.
  ///
  /// In en, this message translates to:
  /// **'SAVE PRESET'**
  String get charEditorSavePreset;

  /// No description provided for @charEditorPresetName.
  ///
  /// In en, this message translates to:
  /// **'Preset Name'**
  String get charEditorPresetName;

  /// No description provided for @charEditorNoPresets.
  ///
  /// In en, this message translates to:
  /// **'No character presets saved'**
  String get charEditorNoPresets;

  /// No description provided for @charEditorSelectSource.
  ///
  /// In en, this message translates to:
  /// **'Source Character'**
  String get charEditorSelectSource;

  /// No description provided for @charEditorSelectTarget.
  ///
  /// In en, this message translates to:
  /// **'Target Character'**
  String get charEditorSelectTarget;

  /// No description provided for @charEditorCharacterN.
  ///
  /// In en, this message translates to:
  /// **'Character {n}'**
  String charEditorCharacterN(int n);

  /// No description provided for @charEditorContinue.
  ///
  /// In en, this message translates to:
  /// **'CONTINUE'**
  String get charEditorContinue;

  /// No description provided for @charEditorParticipants.
  ///
  /// In en, this message translates to:
  /// **'PARTICIPANTS'**
  String get charEditorParticipants;

  /// No description provided for @charEditorSourceTarget.
  ///
  /// In en, this message translates to:
  /// **'SOURCE → TARGET'**
  String get charEditorSourceTarget;

  /// No description provided for @charEditorMutual.
  ///
  /// In en, this message translates to:
  /// **'MUTUAL'**
  String get charEditorMutual;

  /// No description provided for @charsSelectOrCreate.
  ///
  /// In en, this message translates to:
  /// **'Select or create a character'**
  String get charsSelectOrCreate;

  /// No description provided for @charsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search…'**
  String get charsSearchHint;

  /// No description provided for @charsGenerateTooltip.
  ///
  /// In en, this message translates to:
  /// **'Generate a character'**
  String get charsGenerateTooltip;

  /// No description provided for @charsTextGenNeedsKey.
  ///
  /// In en, this message translates to:
  /// **'Requires text generation (set an API key first)'**
  String get charsTextGenNeedsKey;

  /// No description provided for @charsTextGenNeedsKeyWardrobe.
  ///
  /// In en, this message translates to:
  /// **'Requires text generation (set an API key in Text Gen settings)'**
  String get charsTextGenNeedsKeyWardrobe;

  /// No description provided for @charsTextGenNoPermission.
  ///
  /// In en, this message translates to:
  /// **'Your account does not have the text generation permission'**
  String get charsTextGenNoPermission;

  /// No description provided for @charsNew.
  ///
  /// In en, this message translates to:
  /// **'New character'**
  String get charsNew;

  /// No description provided for @charsNewDefaultName.
  ///
  /// In en, this message translates to:
  /// **'New Character'**
  String get charsNewDefaultName;

  /// No description provided for @charsEmptyList.
  ///
  /// In en, this message translates to:
  /// **'No characters yet'**
  String get charsEmptyList;

  /// No description provided for @charsUnnamed.
  ///
  /// In en, this message translates to:
  /// **'(unnamed)'**
  String get charsUnnamed;

  /// No description provided for @charsGenerated.
  ///
  /// In en, this message translates to:
  /// **'Character generated'**
  String get charsGenerated;

  /// No description provided for @charsAddedToPrompt.
  ///
  /// In en, this message translates to:
  /// **'Added to prompt'**
  String get charsAddedToPrompt;

  /// No description provided for @charsNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Character name'**
  String get charsNamePlaceholder;

  /// No description provided for @charsPhotoshoot.
  ///
  /// In en, this message translates to:
  /// **'Photoshoot'**
  String get charsPhotoshoot;

  /// No description provided for @charsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete character'**
  String get charsDelete;

  /// No description provided for @charsDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\" and its wardrobe?'**
  String charsDeleteMessage(String name);

  /// No description provided for @charsGender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get charsGender;

  /// No description provided for @charsGenderUnspecified.
  ///
  /// In en, this message translates to:
  /// **'(unspecified)'**
  String get charsGenderUnspecified;

  /// No description provided for @charsGenderFemale.
  ///
  /// In en, this message translates to:
  /// **'female'**
  String get charsGenderFemale;

  /// No description provided for @charsGenderMale.
  ///
  /// In en, this message translates to:
  /// **'male'**
  String get charsGenderMale;

  /// No description provided for @charsGenderNonbinary.
  ///
  /// In en, this message translates to:
  /// **'non-binary'**
  String get charsGenderNonbinary;

  /// No description provided for @charsTint.
  ///
  /// In en, this message translates to:
  /// **'Tint'**
  String get charsTint;

  /// No description provided for @charsTintAccent.
  ///
  /// In en, this message translates to:
  /// **'Accent'**
  String get charsTintAccent;

  /// No description provided for @charsTintAccent2.
  ///
  /// In en, this message translates to:
  /// **'Accent 2'**
  String get charsTintAccent2;

  /// No description provided for @charsTintBg.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get charsTintBg;

  /// No description provided for @charsIdentityTags.
  ///
  /// In en, this message translates to:
  /// **'Identity tags — no clothing here'**
  String get charsIdentityTags;

  /// No description provided for @charsBaseLabel.
  ///
  /// In en, this message translates to:
  /// **'base — 1girl/1boy, ethnicity, age, permanent marks'**
  String get charsBaseLabel;

  /// No description provided for @charsFaceLabel.
  ///
  /// In en, this message translates to:
  /// **'face — eye colour/shape, brows, nose, lips'**
  String get charsFaceLabel;

  /// No description provided for @charsHairLabel.
  ///
  /// In en, this message translates to:
  /// **'hair — colour, length, style, texture'**
  String get charsHairLabel;

  /// No description provided for @charsBodyLabel.
  ///
  /// In en, this message translates to:
  /// **'body — build, proportions, chest'**
  String get charsBodyLabel;

  /// No description provided for @charsNegativeLabel.
  ///
  /// In en, this message translates to:
  /// **'negative — injected into the UC when this character is used'**
  String get charsNegativeLabel;

  /// No description provided for @charsNsfwSection.
  ///
  /// In en, this message translates to:
  /// **'NSFW sub-buckets (optional)'**
  String get charsNsfwSection;

  /// No description provided for @charsStyleSection.
  ///
  /// In en, this message translates to:
  /// **'Style identity & description (optional)'**
  String get charsStyleSection;

  /// No description provided for @charsSoulSection.
  ///
  /// In en, this message translates to:
  /// **'Personality / soul (optional)'**
  String get charsSoulSection;

  /// No description provided for @charsNsfwTop.
  ///
  /// In en, this message translates to:
  /// **'nsfw top'**
  String get charsNsfwTop;

  /// No description provided for @charsNsfwBottom.
  ///
  /// In en, this message translates to:
  /// **'nsfw bottom'**
  String get charsNsfwBottom;

  /// No description provided for @charsNsfwAlways.
  ///
  /// In en, this message translates to:
  /// **'nsfw always'**
  String get charsNsfwAlways;

  /// No description provided for @charsArtistTag.
  ///
  /// In en, this message translates to:
  /// **'artist tag'**
  String get charsArtistTag;

  /// No description provided for @charsStylePrefix.
  ///
  /// In en, this message translates to:
  /// **'style prefix'**
  String get charsStylePrefix;

  /// No description provided for @charsDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'character description (natural language; not used by NAI image gen)'**
  String get charsDescriptionLabel;

  /// No description provided for @charsSoulLabel.
  ///
  /// In en, this message translates to:
  /// **'soul — long-form personality doc (not used by image gen)'**
  String get charsSoulLabel;

  /// No description provided for @charsCombinedTags.
  ///
  /// In en, this message translates to:
  /// **'Combined tags (preview — body + primary outfit)'**
  String get charsCombinedTags;

  /// No description provided for @charsEmptyValue.
  ///
  /// In en, this message translates to:
  /// **'(empty)'**
  String get charsEmptyValue;

  /// No description provided for @charsWardrobe.
  ///
  /// In en, this message translates to:
  /// **'Wardrobe'**
  String get charsWardrobe;

  /// No description provided for @charsGenerateOutfitsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Generate outfits with text generation'**
  String get charsGenerateOutfitsTooltip;

  /// No description provided for @charsGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating…'**
  String get charsGenerating;

  /// No description provided for @charsGenerateOutfits.
  ///
  /// In en, this message translates to:
  /// **'Generate outfits'**
  String get charsGenerateOutfits;

  /// No description provided for @charsNewOutfit.
  ///
  /// In en, this message translates to:
  /// **'New outfit'**
  String get charsNewOutfit;

  /// No description provided for @charsNoOutfits.
  ///
  /// In en, this message translates to:
  /// **'No outfits yet — add one or generate a set.'**
  String get charsNoOutfits;

  /// No description provided for @charsDeleteOutfitTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete outfit'**
  String get charsDeleteOutfitTitle;

  /// No description provided for @charsDeleteOutfitMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String charsDeleteOutfitMessage(String name);

  /// No description provided for @charsNewOutfitDefaultName.
  ///
  /// In en, this message translates to:
  /// **'New Outfit'**
  String get charsNewOutfitDefaultName;

  /// No description provided for @charsTextGenNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Text generation is not configured'**
  String get charsTextGenNotConfigured;

  /// No description provided for @charsNoOutfitsReturned.
  ///
  /// In en, this message translates to:
  /// **'No outfits returned'**
  String get charsNoOutfitsReturned;

  /// No description provided for @charsOutfitsAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 outfit} other{Added {count} outfits}}'**
  String charsOutfitsAdded(int count);

  /// No description provided for @charsGenerationFailed.
  ///
  /// In en, this message translates to:
  /// **'Generation failed: {error}'**
  String charsGenerationFailed(String error);

  /// No description provided for @charsWear.
  ///
  /// In en, this message translates to:
  /// **'Wear'**
  String get charsWear;

  /// No description provided for @charsState.
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get charsState;

  /// No description provided for @charsSetPrimary.
  ///
  /// In en, this message translates to:
  /// **'Set as primary outfit'**
  String get charsSetPrimary;

  /// No description provided for @charsEditOutfit.
  ///
  /// In en, this message translates to:
  /// **'Edit outfit'**
  String get charsEditOutfit;

  /// No description provided for @charsOutfitName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get charsOutfitName;

  /// No description provided for @charsOutfitNameHint.
  ///
  /// In en, this message translates to:
  /// **'Rainy Day Chic'**
  String get charsOutfitNameHint;

  /// No description provided for @charsClothingTags.
  ///
  /// In en, this message translates to:
  /// **'Clothing tags (4–7 garments)'**
  String get charsClothingTags;

  /// No description provided for @charsNegativeTagsOptional.
  ///
  /// In en, this message translates to:
  /// **'Negative tags (optional)'**
  String get charsNegativeTagsOptional;

  /// No description provided for @charsSeasons.
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get charsSeasons;

  /// No description provided for @charsWeatherLabel.
  ///
  /// In en, this message translates to:
  /// **'Weather'**
  String get charsWeatherLabel;

  /// No description provided for @charsActivities.
  ///
  /// In en, this message translates to:
  /// **'Activities'**
  String get charsActivities;

  /// No description provided for @charsTimeSlots.
  ///
  /// In en, this message translates to:
  /// **'Time slots'**
  String get charsTimeSlots;

  /// No description provided for @charsComfortTemp.
  ///
  /// In en, this message translates to:
  /// **'Comfortable temperature  {start}°C – {end}°C'**
  String charsComfortTemp(int start, int end);

  /// No description provided for @charsDefaultOutfitName.
  ///
  /// In en, this message translates to:
  /// **'Outfit'**
  String get charsDefaultOutfitName;

  /// No description provided for @charsGenerateOutfitsTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate outfits'**
  String get charsGenerateOutfitsTitle;

  /// No description provided for @charsHowMany.
  ///
  /// In en, this message translates to:
  /// **'How many: {count}'**
  String charsHowMany(int count);

  /// No description provided for @charsEraHint.
  ///
  /// In en, this message translates to:
  /// **'Era / setting hint (optional)'**
  String get charsEraHint;

  /// No description provided for @charsEraHintExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1920s Paris, Heian-era Japan, near-future'**
  String get charsEraHintExample;

  /// No description provided for @charsVibeHint.
  ///
  /// In en, this message translates to:
  /// **'Vibe hint (optional)'**
  String get charsVibeHint;

  /// No description provided for @charsVibeHintExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. cozy academia, gothic, beachy minimalist'**
  String get charsVibeHintExample;

  /// No description provided for @charsGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get charsGenerate;

  /// No description provided for @charsStateNoGarments.
  ///
  /// In en, this message translates to:
  /// **'No classifiable garments in this outfit\'s tags.'**
  String get charsStateNoGarments;

  /// No description provided for @charsOutfitState.
  ///
  /// In en, this message translates to:
  /// **'Outfit state'**
  String get charsOutfitState;

  /// No description provided for @charsDishevelled.
  ///
  /// In en, this message translates to:
  /// **'Dishevelled'**
  String get charsDishevelled;

  /// No description provided for @charsResetIntact.
  ///
  /// In en, this message translates to:
  /// **'Reset to intact'**
  String get charsResetIntact;

  /// No description provided for @charsReparse.
  ///
  /// In en, this message translates to:
  /// **'Re-parse from tags'**
  String get charsReparse;

  /// No description provided for @charsConcealed.
  ///
  /// In en, this message translates to:
  /// **'concealed'**
  String get charsConcealed;

  /// No description provided for @charsRenderedTags.
  ///
  /// In en, this message translates to:
  /// **'Rendered tags'**
  String get charsRenderedTags;

  /// No description provided for @charsApplyToPrompt.
  ///
  /// In en, this message translates to:
  /// **'Apply to prompt'**
  String get charsApplyToPrompt;

  /// No description provided for @charsUseTheseTags.
  ///
  /// In en, this message translates to:
  /// **'Use these tags'**
  String get charsUseTheseTags;

  /// No description provided for @charsTopPrefix.
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get charsTopPrefix;

  /// No description provided for @charsBottomPrefix.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get charsBottomPrefix;

  /// No description provided for @charsGenTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate character'**
  String get charsGenTitle;

  /// No description provided for @charsGenVibe.
  ///
  /// In en, this message translates to:
  /// **'Vibe (optional)'**
  String get charsGenVibe;

  /// No description provided for @charsGenVibeHint.
  ///
  /// In en, this message translates to:
  /// **'describe the vibe — e.g. \"weary war veteran turned baker\" — blank lets the model pick'**
  String get charsGenVibeHint;

  /// No description provided for @charsGenGenderAny.
  ///
  /// In en, this message translates to:
  /// **'Any (model picks)'**
  String get charsGenGenderAny;

  /// No description provided for @charsGenEra.
  ///
  /// In en, this message translates to:
  /// **'Era / time period'**
  String get charsGenEra;

  /// No description provided for @charsGenLocation.
  ///
  /// In en, this message translates to:
  /// **'Location (optional)'**
  String get charsGenLocation;

  /// No description provided for @charsGenLocationHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. a coastal town in Portugal, Winterfell — blank lets the model pick'**
  String get charsGenLocationHint;

  /// No description provided for @charsGenNsfw.
  ///
  /// In en, this message translates to:
  /// **'NSFW tags'**
  String get charsGenNsfw;

  /// No description provided for @charsGenNsfwHint.
  ///
  /// In en, this message translates to:
  /// **'also request the split nsfw_* tag buckets'**
  String get charsGenNsfwHint;

  /// No description provided for @charsGenStyle.
  ///
  /// In en, this message translates to:
  /// **'Style (optional)'**
  String get charsGenStyle;

  /// No description provided for @charsGenStyleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. an artist tag — blank lets the model pick'**
  String get charsGenStyleHint;

  /// No description provided for @charsGenWardrobe.
  ///
  /// In en, this message translates to:
  /// **'Starter wardrobe: {count, plural, =1{1 outfit} other{{count} outfits}}'**
  String charsGenWardrobe(int count);

  /// No description provided for @charsGenMeetNote.
  ///
  /// In en, this message translates to:
  /// **'plus the \"meet\" outfit (always generated).'**
  String get charsGenMeetNote;

  /// No description provided for @charsGenProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Generating character'**
  String get charsGenProgressTitle;

  /// No description provided for @charsGenPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get charsGenPreparing;

  /// No description provided for @charsGenProgressNote.
  ///
  /// In en, this message translates to:
  /// **'This makes several model calls — on a free/Tablet-tier token a long personality may take a few continuation passes.'**
  String get charsGenProgressNote;

  /// No description provided for @jukeboxTitle.
  ///
  /// In en, this message translates to:
  /// **'JUKEBOX'**
  String get jukeboxTitle;

  /// No description provided for @jukeboxShuffleAll.
  ///
  /// In en, this message translates to:
  /// **'SHUFFLE ALL'**
  String get jukeboxShuffleAll;

  /// No description provided for @jukeboxPlayAll.
  ///
  /// In en, this message translates to:
  /// **'PLAY ALL'**
  String get jukeboxPlayAll;

  /// No description provided for @jukeboxNoSongPlaying.
  ///
  /// In en, this message translates to:
  /// **'NO SONG PLAYING'**
  String get jukeboxNoSongPlaying;

  /// No description provided for @jukeboxNowPlaying.
  ///
  /// In en, this message translates to:
  /// **'NOW PLAYING'**
  String get jukeboxNowPlaying;

  /// No description provided for @jukeboxSoundFont.
  ///
  /// In en, this message translates to:
  /// **'SOUNDFONT'**
  String get jukeboxSoundFont;

  /// No description provided for @jukeboxSettings.
  ///
  /// In en, this message translates to:
  /// **'SETTINGS'**
  String get jukeboxSettings;

  /// No description provided for @jukeboxQueueEmpty.
  ///
  /// In en, this message translates to:
  /// **'QUEUE IS EMPTY'**
  String get jukeboxQueueEmpty;

  /// No description provided for @jukeboxRepeat.
  ///
  /// In en, this message translates to:
  /// **'REPEAT'**
  String get jukeboxRepeat;

  /// No description provided for @jukeboxShuffle.
  ///
  /// In en, this message translates to:
  /// **'SHUFFLE'**
  String get jukeboxShuffle;

  /// No description provided for @jukeboxOn.
  ///
  /// In en, this message translates to:
  /// **'ON'**
  String get jukeboxOn;

  /// No description provided for @jukeboxOff.
  ///
  /// In en, this message translates to:
  /// **'OFF'**
  String get jukeboxOff;

  /// No description provided for @jukeboxAddToQueue.
  ///
  /// In en, this message translates to:
  /// **'Add to queue'**
  String get jukeboxAddToQueue;

  /// No description provided for @jukeboxMusicUnavailable.
  ///
  /// In en, this message translates to:
  /// **'MUSIC PLAYBACK UNAVAILABLE'**
  String get jukeboxMusicUnavailable;

  /// No description provided for @jukeboxDllMissing.
  ///
  /// In en, this message translates to:
  /// **'FluidSynth DLL not found'**
  String get jukeboxDllMissing;

  /// No description provided for @jukeboxCategoryAll.
  ///
  /// In en, this message translates to:
  /// **'ALL'**
  String get jukeboxCategoryAll;

  /// No description provided for @jukeboxCategoryClassical.
  ///
  /// In en, this message translates to:
  /// **'CLASSICAL'**
  String get jukeboxCategoryClassical;

  /// No description provided for @jukeboxCategoryAnime.
  ///
  /// In en, this message translates to:
  /// **'ANIME'**
  String get jukeboxCategoryAnime;

  /// No description provided for @jukeboxCategoryGame.
  ///
  /// In en, this message translates to:
  /// **'GAME'**
  String get jukeboxCategoryGame;

  /// No description provided for @jukeboxCategoryJazz.
  ///
  /// In en, this message translates to:
  /// **'JAZZ'**
  String get jukeboxCategoryJazz;

  /// No description provided for @jukeboxCategoryAmbient.
  ///
  /// In en, this message translates to:
  /// **'AMBIENT'**
  String get jukeboxCategoryAmbient;

  /// No description provided for @jukeboxCategoryHoliday.
  ///
  /// In en, this message translates to:
  /// **'HOLIDAY'**
  String get jukeboxCategoryHoliday;

  /// No description provided for @jukeboxCategoryMeme.
  ///
  /// In en, this message translates to:
  /// **'MEME'**
  String get jukeboxCategoryMeme;

  /// No description provided for @jukeboxCategoryRock.
  ///
  /// In en, this message translates to:
  /// **'ROCK'**
  String get jukeboxCategoryRock;

  /// No description provided for @mlModels.
  ///
  /// In en, this message translates to:
  /// **'ML MODELS'**
  String get mlModels;

  /// No description provided for @mlBgRemoval.
  ///
  /// In en, this message translates to:
  /// **'BACKGROUND REMOVAL'**
  String get mlBgRemoval;

  /// No description provided for @mlUpscaling.
  ///
  /// In en, this message translates to:
  /// **'UPSCALING'**
  String get mlUpscaling;

  /// No description provided for @mlSegmentation.
  ///
  /// In en, this message translates to:
  /// **'SEGMENTATION'**
  String get mlSegmentation;

  /// No description provided for @mlDownload.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOAD'**
  String get mlDownload;

  /// No description provided for @mlDownloaded.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOADED'**
  String get mlDownloaded;

  /// No description provided for @mlRetry.
  ///
  /// In en, this message translates to:
  /// **'RETRY'**
  String get mlRetry;

  /// No description provided for @mlCancel.
  ///
  /// In en, this message translates to:
  /// **'CANCEL'**
  String get mlCancel;

  /// No description provided for @mlDelete.
  ///
  /// In en, this message translates to:
  /// **'DELETE'**
  String get mlDelete;

  /// No description provided for @mlRemoveBg.
  ///
  /// In en, this message translates to:
  /// **'REMOVE BG'**
  String get mlRemoveBg;

  /// No description provided for @mlUpscale.
  ///
  /// In en, this message translates to:
  /// **'UPSCALE'**
  String get mlUpscale;

  /// No description provided for @mlSegment.
  ///
  /// In en, this message translates to:
  /// **'SEGMENT'**
  String get mlSegment;

  /// No description provided for @mlCanvas.
  ///
  /// In en, this message translates to:
  /// **'CANVAS'**
  String get mlCanvas;

  /// No description provided for @mlSave.
  ///
  /// In en, this message translates to:
  /// **'SAVE'**
  String get mlSave;

  /// No description provided for @mlDiscard.
  ///
  /// In en, this message translates to:
  /// **'DISCARD'**
  String get mlDiscard;

  /// No description provided for @mlAddPoint.
  ///
  /// In en, this message translates to:
  /// **'ADD'**
  String get mlAddPoint;

  /// No description provided for @mlRemovePoint.
  ///
  /// In en, this message translates to:
  /// **'REMOVE'**
  String get mlRemovePoint;

  /// No description provided for @mlBack.
  ///
  /// In en, this message translates to:
  /// **'BACK'**
  String get mlBack;

  /// No description provided for @mlEncodingImage.
  ///
  /// In en, this message translates to:
  /// **'Encoding image...'**
  String get mlEncodingImage;

  /// No description provided for @mlTapToSelect.
  ///
  /// In en, this message translates to:
  /// **'Tap on the image to select a region'**
  String get mlTapToSelect;

  /// No description provided for @mlUndoPoint.
  ///
  /// In en, this message translates to:
  /// **'Undo last point'**
  String get mlUndoPoint;

  /// No description provided for @mlClearPoints.
  ///
  /// In en, this message translates to:
  /// **'Clear all points'**
  String get mlClearPoints;

  /// No description provided for @mlPointCount.
  ///
  /// In en, this message translates to:
  /// **'{count} points'**
  String mlPointCount(int count);

  /// No description provided for @mlOpacity.
  ///
  /// In en, this message translates to:
  /// **'OPACITY'**
  String get mlOpacity;

  /// No description provided for @mlEdgeRefine.
  ///
  /// In en, this message translates to:
  /// **'EDGE REFINE'**
  String get mlEdgeRefine;

  /// No description provided for @mlThreshold.
  ///
  /// In en, this message translates to:
  /// **'THRESHOLD'**
  String get mlThreshold;

  /// No description provided for @mlFeather.
  ///
  /// In en, this message translates to:
  /// **'FEATHER'**
  String get mlFeather;

  /// No description provided for @mlDone.
  ///
  /// In en, this message translates to:
  /// **'DONE'**
  String get mlDone;

  /// No description provided for @mlUpscaleCompare.
  ///
  /// In en, this message translates to:
  /// **'UPSCALE COMPARE'**
  String get mlUpscaleCompare;

  /// No description provided for @mlSaved.
  ///
  /// In en, this message translates to:
  /// **'SAVED'**
  String get mlSaved;

  /// No description provided for @mlSavedFile.
  ///
  /// In en, this message translates to:
  /// **'SAVED: {name}'**
  String mlSavedFile(String name);

  /// No description provided for @mlTierFast.
  ///
  /// In en, this message translates to:
  /// **'FAST'**
  String get mlTierFast;

  /// No description provided for @mlTierBalanced.
  ///
  /// In en, this message translates to:
  /// **'BALANCED'**
  String get mlTierBalanced;

  /// No description provided for @mlTierBalancedShort.
  ///
  /// In en, this message translates to:
  /// **'BAL'**
  String get mlTierBalancedShort;

  /// No description provided for @mlTierQuality.
  ///
  /// In en, this message translates to:
  /// **'QUALITY'**
  String get mlTierQuality;

  /// No description provided for @mlUpscalingImages.
  ///
  /// In en, this message translates to:
  /// **'UPSCALING IMAGES'**
  String get mlUpscalingImages;

  /// No description provided for @mlUpscaleFailed.
  ///
  /// In en, this message translates to:
  /// **'UPSCALE FAILED'**
  String get mlUpscaleFailed;

  /// No description provided for @mlRecommended.
  ///
  /// In en, this message translates to:
  /// **'RECOMMENDED'**
  String get mlRecommended;

  /// No description provided for @mlMayBeSlow.
  ///
  /// In en, this message translates to:
  /// **'MAY BE SLOW'**
  String get mlMayBeSlow;

  /// No description provided for @mlNotRecommended.
  ///
  /// In en, this message translates to:
  /// **'NOT RECOMMENDED'**
  String get mlNotRecommended;

  /// No description provided for @mlNotAvailableOnPlatform.
  ///
  /// In en, this message translates to:
  /// **'NOT AVAILABLE ON THIS PLATFORM'**
  String get mlNotAvailableOnPlatform;

  /// No description provided for @mlLowRamWarning.
  ///
  /// In en, this message translates to:
  /// **'LOW RAM — MAY CRASH'**
  String get mlLowRamWarning;

  /// No description provided for @mlDesktopOnlyMayCrash.
  ///
  /// In en, this message translates to:
  /// **'DESKTOP ONLY — MAY CRASH'**
  String get mlDesktopOnlyMayCrash;

  /// No description provided for @mlDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get mlDownloadFailed;

  /// No description provided for @mlManagerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Download and manage on-device ML models for background removal and upscaling.'**
  String get mlManagerSubtitle;

  /// No description provided for @mlNoModelsDownloaded.
  ///
  /// In en, this message translates to:
  /// **'No models downloaded'**
  String get mlNoModelsDownloaded;

  /// No description provided for @mlModelsDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Models downloaded: {count} · {size}'**
  String mlModelsDownloaded(int count, String size);

  /// No description provided for @mlMobileApiNote.
  ///
  /// In en, this message translates to:
  /// **'On mobile devices, upscaling and background removal use the NovelAI API. Local ML models are only available on desktop.'**
  String get mlMobileApiNote;

  /// No description provided for @mlSegmentationNote.
  ///
  /// In en, this message translates to:
  /// **'Interactive object selection using SAM. Downloads both encoder and decoder.'**
  String get mlSegmentationNote;

  /// No description provided for @mlUnknownModels.
  ///
  /// In en, this message translates to:
  /// **'UNKNOWN MODELS'**
  String get mlUnknownModels;

  /// No description provided for @mlUnknownModelsNote.
  ///
  /// In en, this message translates to:
  /// **'Legacy or unrecognized .onnx/.ort files. Delete to free disk space.'**
  String get mlUnknownModelsNote;

  /// No description provided for @mlDeleteModelTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}?'**
  String mlDeleteModelTitle(String name);

  /// No description provided for @mlDeleteModelMessage.
  ///
  /// In en, this message translates to:
  /// **'This will free {size} of disk space.'**
  String mlDeleteModelMessage(String size);

  /// No description provided for @mlRecommendedForDevice.
  ///
  /// In en, this message translates to:
  /// **'RECOMMENDED FOR YOUR DEVICE'**
  String get mlRecommendedForDevice;

  /// No description provided for @mlSlowOnDevice.
  ///
  /// In en, this message translates to:
  /// **'MAY BE SLOW ON THIS DEVICE'**
  String get mlSlowOnDevice;

  /// No description provided for @mlNaiApiUpscale.
  ///
  /// In en, this message translates to:
  /// **'NOVELAI API UPSCALE'**
  String get mlNaiApiUpscale;

  /// No description provided for @mlNaiApiUpscaleDesc.
  ///
  /// In en, this message translates to:
  /// **'Up to 4x server-side upscaling via NovelAI API. Requires API key. No download needed.'**
  String get mlNaiApiUpscaleDesc;

  /// No description provided for @mlNaiApiBgRemoval.
  ///
  /// In en, this message translates to:
  /// **'NOVELAI API BG REMOVAL'**
  String get mlNaiApiBgRemoval;

  /// No description provided for @mlNaiApiBgRemovalDesc.
  ///
  /// In en, this message translates to:
  /// **'Server-side background removal via NovelAI API. Requires API key. No download needed.'**
  String get mlNaiApiBgRemovalDesc;

  /// No description provided for @mlCloud.
  ///
  /// In en, this message translates to:
  /// **'CLOUD'**
  String get mlCloud;

  /// No description provided for @mlNoApiKey.
  ///
  /// In en, this message translates to:
  /// **'NO API KEY SET'**
  String get mlNoApiKey;

  /// No description provided for @mlTierQualityShort.
  ///
  /// In en, this message translates to:
  /// **'HQ'**
  String get mlTierQualityShort;

  /// No description provided for @mlDeviceMobile.
  ///
  /// In en, this message translates to:
  /// **'MOBILE'**
  String get mlDeviceMobile;

  /// No description provided for @mlDeviceDesktop.
  ///
  /// In en, this message translates to:
  /// **'DESKTOP'**
  String get mlDeviceDesktop;

  /// No description provided for @mlDeviceBoth.
  ///
  /// In en, this message translates to:
  /// **'BOTH'**
  String get mlDeviceBoth;

  /// No description provided for @mlBgRemovedAndSaved.
  ///
  /// In en, this message translates to:
  /// **'BG REMOVED & SAVED'**
  String get mlBgRemovedAndSaved;

  /// No description provided for @mlBgRemovedCount.
  ///
  /// In en, this message translates to:
  /// **'BG REMOVED: {completed}/{total} IMAGES'**
  String mlBgRemovedCount(int completed, int total);

  /// No description provided for @mlUpscaledCount.
  ///
  /// In en, this message translates to:
  /// **'UPSCALED: {completed}/{total} IMAGES'**
  String mlUpscaledCount(int completed, int total);

  /// No description provided for @mlBgRemovedSavedAs.
  ///
  /// In en, this message translates to:
  /// **'BG REMOVED: SAVED AS {name}'**
  String mlBgRemovedSavedAs(String name);

  /// No description provided for @toolsDirectorTools.
  ///
  /// In en, this message translates to:
  /// **'Director Tools'**
  String get toolsDirectorTools;

  /// No description provided for @toolsEnhance.
  ///
  /// In en, this message translates to:
  /// **'Enhance'**
  String get toolsEnhance;

  /// No description provided for @toolDiscardResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard result?'**
  String get toolDiscardResultTitle;

  /// No description provided for @toolDiscardResultMessage.
  ///
  /// In en, this message translates to:
  /// **'This result has not been saved. Going back discards it.'**
  String get toolDiscardResultMessage;

  /// No description provided for @toolDiscardResultConfirm.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get toolDiscardResultConfirm;

  /// No description provided for @directorToolsTitle.
  ///
  /// In en, this message translates to:
  /// **'DIRECTOR TOOLS'**
  String get directorToolsTitle;

  /// No description provided for @directorToolsDesc.
  ///
  /// In en, this message translates to:
  /// **'Server-side image manipulation: remove backgrounds, extract line art, colorize, and more'**
  String get directorToolsDesc;

  /// No description provided for @directorToolsUseCurrent.
  ///
  /// In en, this message translates to:
  /// **'USE CURRENT GENERATION'**
  String get directorToolsUseCurrent;

  /// No description provided for @directorToolsUseCurrentDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the last generated image as source'**
  String get directorToolsUseCurrentDesc;

  /// No description provided for @directorToolsSelectTool.
  ///
  /// In en, this message translates to:
  /// **'SELECT TOOL'**
  String get directorToolsSelectTool;

  /// No description provided for @directorToolsProcess.
  ///
  /// In en, this message translates to:
  /// **'PROCESS'**
  String get directorToolsProcess;

  /// No description provided for @directorToolsProcessing.
  ///
  /// In en, this message translates to:
  /// **'PROCESSING...'**
  String get directorToolsProcessing;

  /// No description provided for @directorToolsDefry.
  ///
  /// In en, this message translates to:
  /// **'DEFRY (TOOL STRENGTH)'**
  String get directorToolsDefry;

  /// No description provided for @directorToolsMood.
  ///
  /// In en, this message translates to:
  /// **'MOOD'**
  String get directorToolsMood;

  /// No description provided for @directorToolBgRemoval.
  ///
  /// In en, this message translates to:
  /// **'Remove BG'**
  String get directorToolBgRemoval;

  /// No description provided for @directorToolLineart.
  ///
  /// In en, this message translates to:
  /// **'Line Art'**
  String get directorToolLineart;

  /// No description provided for @directorToolSketch.
  ///
  /// In en, this message translates to:
  /// **'Sketch'**
  String get directorToolSketch;

  /// No description provided for @directorToolColorize.
  ///
  /// In en, this message translates to:
  /// **'Colorize'**
  String get directorToolColorize;

  /// No description provided for @directorToolEmotion.
  ///
  /// In en, this message translates to:
  /// **'Emotion'**
  String get directorToolEmotion;

  /// No description provided for @directorToolDeclutter.
  ///
  /// In en, this message translates to:
  /// **'Declutter'**
  String get directorToolDeclutter;

  /// No description provided for @moodNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get moodNeutral;

  /// No description provided for @moodHappy.
  ///
  /// In en, this message translates to:
  /// **'Happy'**
  String get moodHappy;

  /// No description provided for @moodSad.
  ///
  /// In en, this message translates to:
  /// **'Sad'**
  String get moodSad;

  /// No description provided for @moodAngry.
  ///
  /// In en, this message translates to:
  /// **'Angry'**
  String get moodAngry;

  /// No description provided for @moodScared.
  ///
  /// In en, this message translates to:
  /// **'Scared'**
  String get moodScared;

  /// No description provided for @moodSurprised.
  ///
  /// In en, this message translates to:
  /// **'Surprised'**
  String get moodSurprised;

  /// No description provided for @moodTired.
  ///
  /// In en, this message translates to:
  /// **'Tired'**
  String get moodTired;

  /// No description provided for @moodExcited.
  ///
  /// In en, this message translates to:
  /// **'Excited'**
  String get moodExcited;

  /// No description provided for @moodNervous.
  ///
  /// In en, this message translates to:
  /// **'Nervous'**
  String get moodNervous;

  /// No description provided for @moodThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get moodThinking;

  /// No description provided for @moodConfused.
  ///
  /// In en, this message translates to:
  /// **'Confused'**
  String get moodConfused;

  /// No description provided for @moodShy.
  ///
  /// In en, this message translates to:
  /// **'Shy'**
  String get moodShy;

  /// No description provided for @moodDisgusted.
  ///
  /// In en, this message translates to:
  /// **'Disgusted'**
  String get moodDisgusted;

  /// No description provided for @moodSmug.
  ///
  /// In en, this message translates to:
  /// **'Smug'**
  String get moodSmug;

  /// No description provided for @moodBored.
  ///
  /// In en, this message translates to:
  /// **'Bored'**
  String get moodBored;

  /// No description provided for @moodLaughing.
  ///
  /// In en, this message translates to:
  /// **'Laughing'**
  String get moodLaughing;

  /// No description provided for @moodIrritated.
  ///
  /// In en, this message translates to:
  /// **'Irritated'**
  String get moodIrritated;

  /// No description provided for @moodAroused.
  ///
  /// In en, this message translates to:
  /// **'Aroused'**
  String get moodAroused;

  /// No description provided for @moodEmbarrassed.
  ///
  /// In en, this message translates to:
  /// **'Embarrassed'**
  String get moodEmbarrassed;

  /// No description provided for @moodWorried.
  ///
  /// In en, this message translates to:
  /// **'Worried'**
  String get moodWorried;

  /// No description provided for @moodLove.
  ///
  /// In en, this message translates to:
  /// **'Love'**
  String get moodLove;

  /// No description provided for @moodDetermined.
  ///
  /// In en, this message translates to:
  /// **'Determined'**
  String get moodDetermined;

  /// No description provided for @moodHurt.
  ///
  /// In en, this message translates to:
  /// **'Hurt'**
  String get moodHurt;

  /// No description provided for @moodPlayful.
  ///
  /// In en, this message translates to:
  /// **'Playful'**
  String get moodPlayful;

  /// No description provided for @directorToolsPrompt.
  ///
  /// In en, this message translates to:
  /// **'PROMPT'**
  String get directorToolsPrompt;

  /// No description provided for @directorToolsPromptHint.
  ///
  /// In en, this message translates to:
  /// **'Optional prompt for colorize/emotion...'**
  String get directorToolsPromptHint;

  /// No description provided for @directorToolsSaved.
  ///
  /// In en, this message translates to:
  /// **'RESULT SAVED TO GALLERY'**
  String get directorToolsSaved;

  /// No description provided for @enhanceTitle.
  ///
  /// In en, this message translates to:
  /// **'ENHANCE'**
  String get enhanceTitle;

  /// No description provided for @enhanceDesc.
  ///
  /// In en, this message translates to:
  /// **'Re-process an image with img2img enhancement'**
  String get enhanceDesc;

  /// No description provided for @enhanceUseCurrent.
  ///
  /// In en, this message translates to:
  /// **'USE CURRENT GENERATION'**
  String get enhanceUseCurrent;

  /// No description provided for @enhanceUseCurrentDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the last generated image as source'**
  String get enhanceUseCurrentDesc;

  /// No description provided for @enhanceProcess.
  ///
  /// In en, this message translates to:
  /// **'ENHANCE'**
  String get enhanceProcess;

  /// No description provided for @enhanceProcessing.
  ///
  /// In en, this message translates to:
  /// **'ENHANCING...'**
  String get enhanceProcessing;

  /// No description provided for @enhancePrompt.
  ///
  /// In en, this message translates to:
  /// **'PROMPT'**
  String get enhancePrompt;

  /// No description provided for @enhanceNegative.
  ///
  /// In en, this message translates to:
  /// **'NEGATIVE'**
  String get enhanceNegative;

  /// No description provided for @enhanceStrength.
  ///
  /// In en, this message translates to:
  /// **'STRENGTH'**
  String get enhanceStrength;

  /// No description provided for @enhanceNoise.
  ///
  /// In en, this message translates to:
  /// **'NOISE'**
  String get enhanceNoise;

  /// No description provided for @enhanceResolutionScale.
  ///
  /// In en, this message translates to:
  /// **'RESOLUTION SCALE'**
  String get enhanceResolutionScale;

  /// No description provided for @enhanceSaved.
  ///
  /// In en, this message translates to:
  /// **'ENHANCED IMAGE SAVED TO GALLERY'**
  String get enhanceSaved;

  /// No description provided for @settingsSeedControl.
  ///
  /// In en, this message translates to:
  /// **'Show Seed Control'**
  String get settingsSeedControl;

  /// No description provided for @settingsSeedControlDesc.
  ///
  /// In en, this message translates to:
  /// **'Display seed value and randomize toggle on the generation screen'**
  String get settingsSeedControlDesc;

  /// No description provided for @settingsShowTooltips.
  ///
  /// In en, this message translates to:
  /// **'Show Tooltips'**
  String get settingsShowTooltips;

  /// No description provided for @settingsShowTooltipsDesc.
  ///
  /// In en, this message translates to:
  /// **'Display helpful tooltips when hovering or long-pressing buttons'**
  String get settingsShowTooltipsDesc;

  /// No description provided for @commonMenu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get commonMenu;

  /// No description provided for @presetLoad.
  ///
  /// In en, this message translates to:
  /// **'Load Preset'**
  String get presetLoad;

  /// No description provided for @settingsStylesToggle.
  ///
  /// In en, this message translates to:
  /// **'Toggle Styles'**
  String get settingsStylesToggle;

  /// No description provided for @canvasLayerToggleVisibility.
  ///
  /// In en, this message translates to:
  /// **'Toggle Visibility'**
  String get canvasLayerToggleVisibility;

  /// No description provided for @mainRefreshAnlas.
  ///
  /// In en, this message translates to:
  /// **'Refresh Anlas'**
  String get mainRefreshAnlas;

  /// No description provided for @enhanceSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get enhanceSettingsTooltip;

  /// No description provided for @directorToolsSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get directorToolsSettingsTooltip;

  /// No description provided for @sidebarCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get sidebarCollapse;

  /// No description provided for @sidebarExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get sidebarExpand;

  /// No description provided for @naiUpscale.
  ///
  /// In en, this message translates to:
  /// **'NAI UPSCALE'**
  String get naiUpscale;

  /// No description provided for @naiUpscaling.
  ///
  /// In en, this message translates to:
  /// **'UPSCALING VIA API...'**
  String get naiUpscaling;

  /// No description provided for @naiUpscaleFailed.
  ///
  /// In en, this message translates to:
  /// **'API upscale failed'**
  String get naiUpscaleFailed;

  /// No description provided for @naiUpscaledCount.
  ///
  /// In en, this message translates to:
  /// **'API UPSCALED: {completed}/{total} IMAGES'**
  String naiUpscaledCount(int completed, int total);

  /// No description provided for @naiApiKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'API key required'**
  String get naiApiKeyRequired;

  /// No description provided for @naiActionNotPermitted.
  ///
  /// In en, this message translates to:
  /// **'Your account is not allowed to use this action'**
  String get naiActionNotPermitted;

  /// No description provided for @naiImageUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Could not read the image size'**
  String get naiImageUnreadable;

  /// No description provided for @comparisonBefore.
  ///
  /// In en, this message translates to:
  /// **'Before'**
  String get comparisonBefore;

  /// No description provided for @comparisonAfter.
  ///
  /// In en, this message translates to:
  /// **'After'**
  String get comparisonAfter;

  /// No description provided for @comparisonSideBySide.
  ///
  /// In en, this message translates to:
  /// **'Side by side'**
  String get comparisonSideBySide;

  /// No description provided for @comparisonSliderMode.
  ///
  /// In en, this message translates to:
  /// **'Slider mode'**
  String get comparisonSliderMode;

  /// No description provided for @comparisonSwap.
  ///
  /// In en, this message translates to:
  /// **'Swap'**
  String get comparisonSwap;

  /// No description provided for @settingsBgRemovalButton.
  ///
  /// In en, this message translates to:
  /// **'BG Removal Button'**
  String get settingsBgRemovalButton;

  /// No description provided for @settingsBgRemovalButtonDesc.
  ///
  /// In en, this message translates to:
  /// **'Show the background removal button on the image viewer'**
  String get settingsBgRemovalButtonDesc;

  /// No description provided for @settingsUpscaleButton.
  ///
  /// In en, this message translates to:
  /// **'Upscale Button'**
  String get settingsUpscaleButton;

  /// No description provided for @settingsUpscaleButtonDesc.
  ///
  /// In en, this message translates to:
  /// **'Show the upscale button on the image viewer'**
  String get settingsUpscaleButtonDesc;

  /// No description provided for @settingsEnhanceButton.
  ///
  /// In en, this message translates to:
  /// **'Enhance Button'**
  String get settingsEnhanceButton;

  /// No description provided for @settingsEnhanceButtonDesc.
  ///
  /// In en, this message translates to:
  /// **'Show the enhance button on the image viewer'**
  String get settingsEnhanceButtonDesc;

  /// No description provided for @settingsDirectorToolsButton.
  ///
  /// In en, this message translates to:
  /// **'Director Tools Button'**
  String get settingsDirectorToolsButton;

  /// No description provided for @settingsDirectorToolsButtonDesc.
  ///
  /// In en, this message translates to:
  /// **'Show the director tools button on the image viewer'**
  String get settingsDirectorToolsButtonDesc;

  /// No description provided for @settingsExportButton.
  ///
  /// In en, this message translates to:
  /// **'Export to Device Button'**
  String get settingsExportButton;

  /// No description provided for @settingsExportButtonDesc.
  ///
  /// In en, this message translates to:
  /// **'Show an export button to save images directly to your photo gallery'**
  String get settingsExportButtonDesc;

  /// No description provided for @settingsAutoExport.
  ///
  /// In en, this message translates to:
  /// **'Auto-Export to Device'**
  String get settingsAutoExport;

  /// No description provided for @settingsAutoExportDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically save generated images to your device photo gallery'**
  String get settingsAutoExportDesc;

  /// No description provided for @settingsExportAlbum.
  ///
  /// In en, this message translates to:
  /// **'Export Album Name'**
  String get settingsExportAlbum;

  /// No description provided for @settingsExportAlbumDesc.
  ///
  /// In en, this message translates to:
  /// **'Device folder/album where exported images are saved'**
  String get settingsExportAlbumDesc;

  /// No description provided for @settingsExportFolder.
  ///
  /// In en, this message translates to:
  /// **'Export Folder'**
  String get settingsExportFolder;

  /// No description provided for @settingsExportFolderDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose a custom folder for exports (SD card, etc). Overrides album name when set.'**
  String get settingsExportFolderDesc;

  /// No description provided for @settingsExportFolderDefault.
  ///
  /// In en, this message translates to:
  /// **'Default (device gallery)'**
  String get settingsExportFolderDefault;

  /// No description provided for @quickActionEnhance.
  ///
  /// In en, this message translates to:
  /// **'Enhance'**
  String get quickActionEnhance;

  /// No description provided for @quickActionDirectorTools.
  ///
  /// In en, this message translates to:
  /// **'Director Tools'**
  String get quickActionDirectorTools;

  /// No description provided for @themeColorBgRemoval.
  ///
  /// In en, this message translates to:
  /// **'BG Removal'**
  String get themeColorBgRemoval;

  /// No description provided for @themeColorUpscale.
  ///
  /// In en, this message translates to:
  /// **'Upscale'**
  String get themeColorUpscale;

  /// No description provided for @jukeboxSynthUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Synthesizer unavailable'**
  String get jukeboxSynthUnavailable;

  /// No description provided for @jukeboxImport.
  ///
  /// In en, this message translates to:
  /// **'IMPORT'**
  String get jukeboxImport;

  /// No description provided for @jukeboxKeyboard.
  ///
  /// In en, this message translates to:
  /// **'KEYBOARD'**
  String get jukeboxKeyboard;

  /// No description provided for @jukeboxGame.
  ///
  /// In en, this message translates to:
  /// **'GAME'**
  String get jukeboxGame;

  /// No description provided for @jukeboxEnd.
  ///
  /// In en, this message translates to:
  /// **'END'**
  String get jukeboxEnd;

  /// No description provided for @jukeboxTempo.
  ///
  /// In en, this message translates to:
  /// **'TEMPO'**
  String get jukeboxTempo;

  /// No description provided for @jukeboxKeyboardHint.
  ///
  /// In en, this message translates to:
  /// **'KEYS: A-L  SHARPS: W,E,T,Y,U,O,P  OCTAVE: Z/X'**
  String get jukeboxKeyboardHint;

  /// No description provided for @jukeboxGameResults.
  ///
  /// In en, this message translates to:
  /// **'RESULTS'**
  String get jukeboxGameResults;

  /// No description provided for @jukeboxGameScore.
  ///
  /// In en, this message translates to:
  /// **'SCORE'**
  String get jukeboxGameScore;

  /// No description provided for @jukeboxGameMaxCombo.
  ///
  /// In en, this message translates to:
  /// **'MAX COMBO'**
  String get jukeboxGameMaxCombo;

  /// No description provided for @jukeboxGameAccuracy.
  ///
  /// In en, this message translates to:
  /// **'ACCURACY'**
  String get jukeboxGameAccuracy;

  /// No description provided for @jukeboxGamePerfect.
  ///
  /// In en, this message translates to:
  /// **'PERFECT'**
  String get jukeboxGamePerfect;

  /// No description provided for @jukeboxGameGreat.
  ///
  /// In en, this message translates to:
  /// **'GREAT'**
  String get jukeboxGameGreat;

  /// No description provided for @jukeboxGameGood.
  ///
  /// In en, this message translates to:
  /// **'GOOD'**
  String get jukeboxGameGood;

  /// No description provided for @jukeboxGameMiss.
  ///
  /// In en, this message translates to:
  /// **'MISS'**
  String get jukeboxGameMiss;

  /// No description provided for @jukeboxHighScores.
  ///
  /// In en, this message translates to:
  /// **'HIGH SCORES'**
  String get jukeboxHighScores;

  /// No description provided for @jukeboxQueueCount.
  ///
  /// In en, this message translates to:
  /// **'QUEUE ({count})'**
  String jukeboxQueueCount(int count);

  /// No description provided for @jukeboxStyle.
  ///
  /// In en, this message translates to:
  /// **'STYLE'**
  String get jukeboxStyle;

  /// No description provided for @jukeboxGameModeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Game Mode'**
  String get jukeboxGameModeTooltip;

  /// No description provided for @jukeboxEndGameTooltip.
  ///
  /// In en, this message translates to:
  /// **'End Game'**
  String get jukeboxEndGameTooltip;

  /// No description provided for @jukeboxImportTooltip.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get jukeboxImportTooltip;

  /// No description provided for @jukeboxShuffleAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Shuffle All'**
  String get jukeboxShuffleAllTooltip;

  /// No description provided for @jukeboxPlayAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Play All'**
  String get jukeboxPlayAllTooltip;

  /// No description provided for @jukeboxKeyboardTooltip.
  ///
  /// In en, this message translates to:
  /// **'Keyboard'**
  String get jukeboxKeyboardTooltip;

  /// No description provided for @jukeboxGameMode.
  ///
  /// In en, this message translates to:
  /// **'GAME MODE'**
  String get jukeboxGameMode;

  /// No description provided for @jukeboxNoSongs.
  ///
  /// In en, this message translates to:
  /// **'NO SONGS'**
  String get jukeboxNoSongs;

  /// No description provided for @jukeboxRecommendedBadge.
  ///
  /// In en, this message translates to:
  /// **'REC'**
  String get jukeboxRecommendedBadge;

  /// No description provided for @jukeboxAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'ANALYZING...'**
  String get jukeboxAnalyzing;

  /// No description provided for @jukeboxNoScoresYet.
  ///
  /// In en, this message translates to:
  /// **'No scores yet'**
  String get jukeboxNoScoresYet;

  /// No description provided for @jukeboxSelectInstrument.
  ///
  /// In en, this message translates to:
  /// **'SELECT INSTRUMENT'**
  String get jukeboxSelectInstrument;

  /// No description provided for @jukeboxPlayGame.
  ///
  /// In en, this message translates to:
  /// **'PLAY GAME'**
  String get jukeboxPlayGame;

  /// No description provided for @jukeboxChannelLabel.
  ///
  /// In en, this message translates to:
  /// **'CH {channel}'**
  String jukeboxChannelLabel(int channel);

  /// No description provided for @jukeboxCombo.
  ///
  /// In en, this message translates to:
  /// **'{count} COMBO'**
  String jukeboxCombo(int count);

  /// No description provided for @jukeboxPressOnTheLine.
  ///
  /// In en, this message translates to:
  /// **'PRESS ON THE LINE'**
  String get jukeboxPressOnTheLine;

  /// No description provided for @jukeboxGradePerfect.
  ///
  /// In en, this message translates to:
  /// **'PERFECT'**
  String get jukeboxGradePerfect;

  /// No description provided for @jukeboxGradeGreat.
  ///
  /// In en, this message translates to:
  /// **'GREAT'**
  String get jukeboxGradeGreat;

  /// No description provided for @jukeboxGradeGood.
  ///
  /// In en, this message translates to:
  /// **'GOOD'**
  String get jukeboxGradeGood;

  /// No description provided for @jukeboxGradeMiss.
  ///
  /// In en, this message translates to:
  /// **'MISS'**
  String get jukeboxGradeMiss;

  /// No description provided for @jukeboxDifficultyEasy.
  ///
  /// In en, this message translates to:
  /// **'EASY'**
  String get jukeboxDifficultyEasy;

  /// No description provided for @jukeboxDifficultyMedium.
  ///
  /// In en, this message translates to:
  /// **'MEDIUM'**
  String get jukeboxDifficultyMedium;

  /// No description provided for @jukeboxDifficultyHard.
  ///
  /// In en, this message translates to:
  /// **'HARD'**
  String get jukeboxDifficultyHard;

  /// No description provided for @jukeboxDifficultyExtreme.
  ///
  /// In en, this message translates to:
  /// **'EXTREME'**
  String get jukeboxDifficultyExtreme;

  /// No description provided for @jukeboxInstrumentAcousticGrandPiano.
  ///
  /// In en, this message translates to:
  /// **'Acoustic Grand Piano'**
  String get jukeboxInstrumentAcousticGrandPiano;

  /// No description provided for @jukeboxInstrumentElectricPiano.
  ///
  /// In en, this message translates to:
  /// **'Electric Piano'**
  String get jukeboxInstrumentElectricPiano;

  /// No description provided for @jukeboxInstrumentHarpsichord.
  ///
  /// In en, this message translates to:
  /// **'Harpsichord'**
  String get jukeboxInstrumentHarpsichord;

  /// No description provided for @jukeboxInstrumentVibraphone.
  ///
  /// In en, this message translates to:
  /// **'Vibraphone'**
  String get jukeboxInstrumentVibraphone;

  /// No description provided for @jukeboxInstrumentXylophone.
  ///
  /// In en, this message translates to:
  /// **'Xylophone'**
  String get jukeboxInstrumentXylophone;

  /// No description provided for @jukeboxInstrumentChurchOrgan.
  ///
  /// In en, this message translates to:
  /// **'Church Organ'**
  String get jukeboxInstrumentChurchOrgan;

  /// No description provided for @jukeboxInstrumentNylonGuitar.
  ///
  /// In en, this message translates to:
  /// **'Nylon Guitar'**
  String get jukeboxInstrumentNylonGuitar;

  /// No description provided for @jukeboxInstrumentSteelGuitar.
  ///
  /// In en, this message translates to:
  /// **'Steel Guitar'**
  String get jukeboxInstrumentSteelGuitar;

  /// No description provided for @jukeboxInstrumentCleanElectricGuitar.
  ///
  /// In en, this message translates to:
  /// **'Clean Electric Guitar'**
  String get jukeboxInstrumentCleanElectricGuitar;

  /// No description provided for @jukeboxInstrumentDistortionGuitar.
  ///
  /// In en, this message translates to:
  /// **'Distortion Guitar'**
  String get jukeboxInstrumentDistortionGuitar;

  /// No description provided for @jukeboxInstrumentAcousticBass.
  ///
  /// In en, this message translates to:
  /// **'Acoustic Bass'**
  String get jukeboxInstrumentAcousticBass;

  /// No description provided for @jukeboxInstrumentElectricBassFinger.
  ///
  /// In en, this message translates to:
  /// **'Electric Bass (Finger)'**
  String get jukeboxInstrumentElectricBassFinger;

  /// No description provided for @jukeboxInstrumentViolin.
  ///
  /// In en, this message translates to:
  /// **'Violin'**
  String get jukeboxInstrumentViolin;

  /// No description provided for @jukeboxInstrumentCello.
  ///
  /// In en, this message translates to:
  /// **'Cello'**
  String get jukeboxInstrumentCello;

  /// No description provided for @jukeboxInstrumentOrchestralHarp.
  ///
  /// In en, this message translates to:
  /// **'Orchestral Harp'**
  String get jukeboxInstrumentOrchestralHarp;

  /// No description provided for @jukeboxInstrumentStringEnsemble.
  ///
  /// In en, this message translates to:
  /// **'String Ensemble'**
  String get jukeboxInstrumentStringEnsemble;

  /// No description provided for @jukeboxInstrumentTrumpet.
  ///
  /// In en, this message translates to:
  /// **'Trumpet'**
  String get jukeboxInstrumentTrumpet;

  /// No description provided for @jukeboxInstrumentFrenchHorn.
  ///
  /// In en, this message translates to:
  /// **'French Horn'**
  String get jukeboxInstrumentFrenchHorn;

  /// No description provided for @jukeboxInstrumentAltoSax.
  ///
  /// In en, this message translates to:
  /// **'Alto Sax'**
  String get jukeboxInstrumentAltoSax;

  /// No description provided for @jukeboxInstrumentFlute.
  ///
  /// In en, this message translates to:
  /// **'Flute'**
  String get jukeboxInstrumentFlute;

  /// No description provided for @jukeboxInstrumentSquareLeadSynth.
  ///
  /// In en, this message translates to:
  /// **'Square Lead (Synth)'**
  String get jukeboxInstrumentSquareLeadSynth;

  /// No description provided for @jukeboxInstrumentLeadVoice.
  ///
  /// In en, this message translates to:
  /// **'Lead 6 (Voice)'**
  String get jukeboxInstrumentLeadVoice;

  /// No description provided for @jukeboxKaraokeBadge.
  ///
  /// In en, this message translates to:
  /// **'KAR'**
  String get jukeboxKaraokeBadge;

  /// No description provided for @jukeboxDeleteCustomSongTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete custom song'**
  String get jukeboxDeleteCustomSongTooltip;

  /// No description provided for @jukeboxDeleteSong.
  ///
  /// In en, this message translates to:
  /// **'DELETE SONG'**
  String get jukeboxDeleteSong;

  /// No description provided for @jukeboxDeleteSongConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete {title}? This will remove the file from disk.'**
  String jukeboxDeleteSongConfirm(String title);

  /// No description provided for @jukeboxStyleHighlight.
  ///
  /// In en, this message translates to:
  /// **'HIGHLIGHT'**
  String get jukeboxStyleHighlight;

  /// No description provided for @jukeboxStyleUpcoming.
  ///
  /// In en, this message translates to:
  /// **'UPCOMING'**
  String get jukeboxStyleUpcoming;

  /// No description provided for @jukeboxStyleNextLine.
  ///
  /// In en, this message translates to:
  /// **'NEXT LINE'**
  String get jukeboxStyleNextLine;

  /// No description provided for @jukeboxStyleGlow.
  ///
  /// In en, this message translates to:
  /// **'GLOW'**
  String get jukeboxStyleGlow;

  /// No description provided for @jukeboxVisualizer.
  ///
  /// In en, this message translates to:
  /// **'VISUALIZER'**
  String get jukeboxVisualizer;

  /// No description provided for @jukeboxToggleVisualizer.
  ///
  /// In en, this message translates to:
  /// **'Toggle visualizer display'**
  String get jukeboxToggleVisualizer;

  /// No description provided for @jukeboxPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get jukeboxPrevious;

  /// No description provided for @jukeboxNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get jukeboxNext;

  /// No description provided for @jukeboxPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get jukeboxPlay;

  /// No description provided for @jukeboxPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get jukeboxPause;

  /// No description provided for @jukeboxMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get jukeboxMute;

  /// No description provided for @jukeboxUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get jukeboxUnmute;

  /// No description provided for @jukeboxRemoveFromQueue.
  ///
  /// In en, this message translates to:
  /// **'Remove from queue'**
  String get jukeboxRemoveFromQueue;

  /// No description provided for @jukeboxFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get jukeboxFullscreen;

  /// No description provided for @jukeboxKaraokeLabel.
  ///
  /// In en, this message translates to:
  /// **'KARAOKE'**
  String get jukeboxKaraokeLabel;

  /// No description provided for @jukeboxBundled.
  ///
  /// In en, this message translates to:
  /// **'BUNDLED'**
  String get jukeboxBundled;

  /// No description provided for @jukeboxSoundfontDownload.
  ///
  /// In en, this message translates to:
  /// **'DOWNLOAD'**
  String get jukeboxSoundfontDownload;

  /// No description provided for @jukeboxSoundfontDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete soundfont'**
  String get jukeboxSoundfontDelete;

  /// No description provided for @jukeboxSoundfontDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'DELETE SOUNDFONT'**
  String get jukeboxSoundfontDeleteTitle;

  /// No description provided for @jukeboxSoundfontDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete {name}? You can re-download it later.'**
  String jukeboxSoundfontDeleteMessage(String name);

  /// No description provided for @jukeboxVizIntensity.
  ///
  /// In en, this message translates to:
  /// **'INTENSITY'**
  String get jukeboxVizIntensity;

  /// No description provided for @jukeboxVizSpeed.
  ///
  /// In en, this message translates to:
  /// **'SPEED'**
  String get jukeboxVizSpeed;

  /// No description provided for @jukeboxVizDensity.
  ///
  /// In en, this message translates to:
  /// **'DENSITY'**
  String get jukeboxVizDensity;

  /// No description provided for @jukeboxFontSize.
  ///
  /// In en, this message translates to:
  /// **'SIZE'**
  String get jukeboxFontSize;

  /// No description provided for @jukeboxResetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'RESET TO DEFAULTS'**
  String get jukeboxResetToDefaults;

  /// No description provided for @jukeboxRepeatMode.
  ///
  /// In en, this message translates to:
  /// **'REPEAT: {mode}'**
  String jukeboxRepeatMode(String mode);

  /// No description provided for @jukeboxShuffleStatus.
  ///
  /// In en, this message translates to:
  /// **'SHUFFLE: {status}'**
  String jukeboxShuffleStatus(String status);

  /// No description provided for @galleryBadgeNaiUpscale.
  ///
  /// In en, this message translates to:
  /// **'NAI UPSCALE'**
  String get galleryBadgeNaiUpscale;

  /// No description provided for @galleryBadgeDirectorTool.
  ///
  /// In en, this message translates to:
  /// **'DIRECTOR: {tool}'**
  String galleryBadgeDirectorTool(String tool);

  /// No description provided for @galleryBadgeEnhanced.
  ///
  /// In en, this message translates to:
  /// **'ENHANCED'**
  String get galleryBadgeEnhanced;

  /// No description provided for @galleryBadgeBgRemoved.
  ///
  /// In en, this message translates to:
  /// **'BG REMOVED'**
  String get galleryBadgeBgRemoved;

  /// No description provided for @galleryBadgeUpscaled.
  ///
  /// In en, this message translates to:
  /// **'UPSCALED'**
  String get galleryBadgeUpscaled;

  /// No description provided for @galleryBgRemovalFailed.
  ///
  /// In en, this message translates to:
  /// **'BG REMOVAL FAILED'**
  String get galleryBgRemovalFailed;

  /// No description provided for @galleryRemovingBackgrounds.
  ///
  /// In en, this message translates to:
  /// **'REMOVING BACKGROUNDS'**
  String get galleryRemovingBackgrounds;

  /// No description provided for @naiUpscaleTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Image too large for NAI upscale ({width}x{height} exceeds 2048px limit per side)'**
  String naiUpscaleTooLarge(int width, int height);

  /// No description provided for @naiRemovingBackground.
  ///
  /// In en, this message translates to:
  /// **'REMOVING BACKGROUND...'**
  String get naiRemovingBackground;

  /// No description provided for @naiBgRemovalFailed.
  ///
  /// In en, this message translates to:
  /// **'NAI BG REMOVAL FAILED'**
  String get naiBgRemovalFailed;

  /// No description provided for @directorToolsFromGallery.
  ///
  /// In en, this message translates to:
  /// **'FROM GALLERY'**
  String get directorToolsFromGallery;

  /// No description provided for @importDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'IMPORT METADATA'**
  String get importDialogTitle;

  /// No description provided for @importCategoryPrompt.
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get importCategoryPrompt;

  /// No description provided for @importCategoryNegative.
  ///
  /// In en, this message translates to:
  /// **'Negative Prompt'**
  String get importCategoryNegative;

  /// No description provided for @importCategoryCharacters.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get importCategoryCharacters;

  /// No description provided for @importCategorySeed.
  ///
  /// In en, this message translates to:
  /// **'Seed'**
  String get importCategorySeed;

  /// No description provided for @importCategoryStyles.
  ///
  /// In en, this message translates to:
  /// **'Styles'**
  String get importCategoryStyles;

  /// No description provided for @importCategorySettings.
  ///
  /// In en, this message translates to:
  /// **'Settings (Resolution, Sampler, Scale)'**
  String get importCategorySettings;

  /// No description provided for @importActionImport.
  ///
  /// In en, this message translates to:
  /// **'IMPORT'**
  String get importActionImport;

  /// No description provided for @importNothingAvailable.
  ///
  /// In en, this message translates to:
  /// **'No importable metadata found'**
  String get importNothingAvailable;

  /// No description provided for @importStylesAutoDetected.
  ///
  /// In en, this message translates to:
  /// **'auto-detected from prompt'**
  String get importStylesAutoDetected;

  /// No description provided for @importStylesEmbedded.
  ///
  /// In en, this message translates to:
  /// **'disable - embedded in prompt'**
  String get importStylesEmbedded;

  /// No description provided for @img2imgOutputRes.
  ///
  /// In en, this message translates to:
  /// **'OUTPUT RESOLUTION'**
  String get img2imgOutputRes;

  /// No description provided for @duplicateImageWarning.
  ///
  /// In en, this message translates to:
  /// **'Image identical to last generation — try a different seed or check your vibes/references'**
  String get duplicateImageWarning;

  /// No description provided for @duplicateImageRandomize.
  ///
  /// In en, this message translates to:
  /// **'Randomize'**
  String get duplicateImageRandomize;

  /// No description provided for @generationNoParametersVaried.
  ///
  /// In en, this message translates to:
  /// **'No parameters varied. Check the seed.'**
  String get generationNoParametersVaried;

  /// No description provided for @generationRandomizeSeed.
  ///
  /// In en, this message translates to:
  /// **'Random seed'**
  String get generationRandomizeSeed;

  /// No description provided for @settingsCredits.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get settingsCredits;

  /// No description provided for @settingsSpecialThanks.
  ///
  /// In en, this message translates to:
  /// **'Special Thanks'**
  String get settingsSpecialThanks;

  /// No description provided for @settingsAnonTesters.
  ///
  /// In en, this message translates to:
  /// **'...and all anonymous bug testers'**
  String get settingsAnonTesters;

  /// No description provided for @settingsLayoutMode.
  ///
  /// In en, this message translates to:
  /// **'Layout Mode'**
  String get settingsLayoutMode;

  /// No description provided for @settingsLayoutModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Control how settings are displayed on wide screens'**
  String get settingsLayoutModeDesc;

  /// No description provided for @settingsLayoutAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get settingsLayoutAuto;

  /// No description provided for @settingsLayoutSidebar.
  ///
  /// In en, this message translates to:
  /// **'Sidebar'**
  String get settingsLayoutSidebar;

  /// No description provided for @settingsLayoutClassic.
  ///
  /// In en, this message translates to:
  /// **'Classic'**
  String get settingsLayoutClassic;

  /// No description provided for @settingsPromptPosition.
  ///
  /// In en, this message translates to:
  /// **'Prompt Position'**
  String get settingsPromptPosition;

  /// No description provided for @settingsPromptPositionDesc.
  ///
  /// In en, this message translates to:
  /// **'Where the prompt input appears in sidebar mode'**
  String get settingsPromptPositionDesc;

  /// No description provided for @settingsPromptLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get settingsPromptLeft;

  /// No description provided for @settingsPromptRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get settingsPromptRight;

  /// No description provided for @settingsSidebarWidth.
  ///
  /// In en, this message translates to:
  /// **'Sidebar Width'**
  String get settingsSidebarWidth;

  /// No description provided for @settingsSidebarWidthDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose compact for a narrower sidebar panel'**
  String get settingsSidebarWidthDesc;

  /// No description provided for @settingsSidebarCompact.
  ///
  /// In en, this message translates to:
  /// **'Compact'**
  String get settingsSidebarCompact;

  /// No description provided for @settingsSidebarNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get settingsSidebarNormal;

  /// No description provided for @toolsTextGen.
  ///
  /// In en, this message translates to:
  /// **'Text Gen'**
  String get toolsTextGen;

  /// No description provided for @textGenTitle.
  ///
  /// In en, this message translates to:
  /// **'Text Generation'**
  String get textGenTitle;

  /// No description provided for @textGenInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get textGenInput;

  /// No description provided for @textGenInputHint.
  ///
  /// In en, this message translates to:
  /// **'The text to continue from…'**
  String get textGenInputHint;

  /// No description provided for @textGenInputNote.
  ///
  /// In en, this message translates to:
  /// **'NovelAI text models continue your text — they don\'t follow chat turns.'**
  String get textGenInputNote;

  /// No description provided for @textGenModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get textGenModel;

  /// No description provided for @textGenModelCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get textGenModelCustom;

  /// No description provided for @textGenParameters.
  ///
  /// In en, this message translates to:
  /// **'Parameters'**
  String get textGenParameters;

  /// No description provided for @textGenPreset.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get textGenPreset;

  /// No description provided for @textGenTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get textGenTemperature;

  /// No description provided for @textGenMaxLength.
  ///
  /// In en, this message translates to:
  /// **'Max length'**
  String get textGenMaxLength;

  /// No description provided for @textGenTopP.
  ///
  /// In en, this message translates to:
  /// **'Top P'**
  String get textGenTopP;

  /// No description provided for @textGenTopK.
  ///
  /// In en, this message translates to:
  /// **'Top K'**
  String get textGenTopK;

  /// No description provided for @textGenRepetitionPenalty.
  ///
  /// In en, this message translates to:
  /// **'Repetition penalty'**
  String get textGenRepetitionPenalty;

  /// No description provided for @textGenPhraseRepPen.
  ///
  /// In en, this message translates to:
  /// **'Phrase rep. pen.'**
  String get textGenPhraseRepPen;

  /// No description provided for @textGenGenerateUntilSentence.
  ///
  /// In en, this message translates to:
  /// **'Generate until sentence end'**
  String get textGenGenerateUntilSentence;

  /// No description provided for @textGenStopStrings.
  ///
  /// In en, this message translates to:
  /// **'Stop strings'**
  String get textGenStopStrings;

  /// No description provided for @textGenStopStringsNote.
  ///
  /// In en, this message translates to:
  /// **'One per line. Output is truncated at the first match (client-side).'**
  String get textGenStopStringsNote;

  /// No description provided for @textGenStopStringsHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. an ending line of dialogue'**
  String get textGenStopStringsHint;

  /// No description provided for @textGenGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get textGenGenerate;

  /// No description provided for @textGenCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get textGenCancel;

  /// No description provided for @textGenContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get textGenContinue;

  /// No description provided for @textGenCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get textGenCopy;

  /// No description provided for @textGenClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get textGenClear;

  /// No description provided for @textGenCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get textGenCopied;

  /// No description provided for @textGenOutput.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get textGenOutput;

  /// No description provided for @textGenOutputEmpty.
  ///
  /// In en, this message translates to:
  /// **'Generated text will appear here.'**
  String get textGenOutputEmpty;

  /// No description provided for @textGenErrNoToken.
  ///
  /// In en, this message translates to:
  /// **'No NovelAI token is set. Add it in Settings.'**
  String get textGenErrNoToken;

  /// No description provided for @textGenErrEmptyInput.
  ///
  /// In en, this message translates to:
  /// **'Enter some text to continue from.'**
  String get textGenErrEmptyInput;

  /// No description provided for @textGenClearConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear output?'**
  String get textGenClearConfirmTitle;

  /// No description provided for @textGenClearConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'The generated text and its reasoning will be removed. Copy it first if you need it.'**
  String get textGenClearConfirmMessage;

  /// No description provided for @textGenHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get textGenHistory;

  /// No description provided for @textGenEnableThinking.
  ///
  /// In en, this message translates to:
  /// **'Enable thinking'**
  String get textGenEnableThinking;

  /// No description provided for @textGenEnableThinkingNote.
  ///
  /// In en, this message translates to:
  /// **'GLM emits a private reasoning block before its answer. Forces non-streaming.'**
  String get textGenEnableThinkingNote;

  /// No description provided for @textGenReasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get textGenReasoning;

  /// No description provided for @serverHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Server History'**
  String get serverHistoryTitle;

  /// No description provided for @serverHistoryAllUsers.
  ///
  /// In en, this message translates to:
  /// **'All Users'**
  String get serverHistoryAllUsers;

  /// No description provided for @serverHistoryRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get serverHistoryRefresh;

  /// No description provided for @serverHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No server history yet'**
  String get serverHistoryEmpty;

  /// No description provided for @serverHistoryImportParameters.
  ///
  /// In en, this message translates to:
  /// **'Import Parameters'**
  String get serverHistoryImportParameters;

  /// No description provided for @serverHistoryImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Parameters imported'**
  String get serverHistoryImportSuccess;

  /// No description provided for @serverHistoryDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get serverHistoryDownload;

  /// No description provided for @serverHistoryDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Hide this item from your history.'**
  String get serverHistoryDeleteConfirm;

  /// No description provided for @serverHistoryBatchImportParameters.
  ///
  /// In en, this message translates to:
  /// **'Import Batch Parameters'**
  String get serverHistoryBatchImportParameters;

  /// No description provided for @serverHistoryBatchImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Batch parameters imported'**
  String get serverHistoryBatchImportSuccess;

  /// No description provided for @serverHistoryBatchDownload.
  ///
  /// In en, this message translates to:
  /// **'Download Batch'**
  String get serverHistoryBatchDownload;

  /// No description provided for @serverHistoryBatchDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Batch'**
  String get serverHistoryBatchDelete;

  /// No description provided for @serverHistoryBatchDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Hide every image in this batch from your history?'**
  String get serverHistoryBatchDeleteConfirm;

  /// No description provided for @serverHistoryDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String serverHistoryDeleteFailed(String error);

  /// No description provided for @serverHistoryDeleteActive.
  ///
  /// In en, this message translates to:
  /// **'Still queued or running; it can be deleted once it finishes.'**
  String get serverHistoryDeleteActive;

  /// No description provided for @serverHistoryLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load history: {error}'**
  String serverHistoryLoadFailed(String error);

  /// No description provided for @serverHistoryRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get serverHistoryRetry;

  /// No description provided for @serverHistoryUsersUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The user list could not be loaded, so the user filter is unavailable.'**
  String get serverHistoryUsersUnavailable;

  /// No description provided for @serverHistoryItemCancelled.
  ///
  /// In en, this message translates to:
  /// **'The task was cancelled. You were not charged.'**
  String get serverHistoryItemCancelled;

  /// No description provided for @quotePointsTooltipFree.
  ///
  /// In en, this message translates to:
  /// **'Free · {points} green points'**
  String quotePointsTooltipFree(int points);

  /// No description provided for @quotePointsTooltipPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid · {points} red points'**
  String quotePointsTooltipPaid(int points);

  /// No description provided for @quoteDiscountNote.
  ///
  /// In en, this message translates to:
  /// **'Green point discount: {percent}%'**
  String quoteDiscountNote(int percent);

  /// No description provided for @quoteInvalidBadge.
  ///
  /// In en, this message translates to:
  /// **'Invalid'**
  String get quoteInvalidBadge;

  /// No description provided for @quoteInvalidTooltip.
  ///
  /// In en, this message translates to:
  /// **'These parameters are outside what the server accepts ({field}).'**
  String quoteInvalidTooltip(String field);

  /// No description provided for @quoteReasonSizeNotFree.
  ///
  /// In en, this message translates to:
  /// **'Size is not a free size'**
  String get quoteReasonSizeNotFree;

  /// No description provided for @quoteReasonStepsOverFreeLimit.
  ///
  /// In en, this message translates to:
  /// **'Steps above the free limit'**
  String get quoteReasonStepsOverFreeLimit;

  /// No description provided for @quoteReasonSmea.
  ///
  /// In en, this message translates to:
  /// **'SMEA enabled'**
  String get quoteReasonSmea;

  /// No description provided for @quoteReasonImageInput.
  ///
  /// In en, this message translates to:
  /// **'Image input (img2img / inpaint)'**
  String get quoteReasonImageInput;

  /// No description provided for @quoteReasonDirectorRefs.
  ///
  /// In en, this message translates to:
  /// **'Precise references'**
  String get quoteReasonDirectorRefs;

  /// No description provided for @quoteReasonVibes.
  ///
  /// In en, this message translates to:
  /// **'Vibe transfer'**
  String get quoteReasonVibes;

  /// No description provided for @quoteReasonAllowanceExhausted.
  ///
  /// In en, this message translates to:
  /// **'Free allowance used up for now'**
  String get quoteReasonAllowanceExhausted;

  /// No description provided for @quoteReasonPaidTool.
  ///
  /// In en, this message translates to:
  /// **'Paid tool'**
  String get quoteReasonPaidTool;

  /// No description provided for @quoteAdjustToFree.
  ///
  /// In en, this message translates to:
  /// **'Make free'**
  String get quoteAdjustToFree;

  /// No description provided for @quoteAdjustToFreeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Set size, steps and SMEA back to what is free'**
  String get quoteAdjustToFreeTooltip;

  /// No description provided for @quoteFreeOnlyNotice.
  ///
  /// In en, this message translates to:
  /// **'Your account can only generate for free. These settings would cost red points:'**
  String get quoteFreeOnlyNotice;

  /// No description provided for @quoteFreeAllowanceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The free allowance is used up for now, so free generation is unavailable for a while.'**
  String get quoteFreeAllowanceUnavailable;

  /// No description provided for @quoteAdjustToFreeAction.
  ///
  /// In en, this message translates to:
  /// **'Adjust to free parameters'**
  String get quoteAdjustToFreeAction;

  /// No description provided for @quoteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Price changed'**
  String get quoteConfirmTitle;

  /// No description provided for @quoteConfirmPriceRed.
  ///
  /// In en, this message translates to:
  /// **'The server price applies: {points} red points.'**
  String quoteConfirmPriceRed(int points);

  /// No description provided for @quoteConfirmPriceGreen.
  ///
  /// In en, this message translates to:
  /// **'The server price applies: {points} green points.'**
  String quoteConfirmPriceGreen(int points);

  /// No description provided for @quoteConfirmShown.
  ///
  /// In en, this message translates to:
  /// **'The price shown was {points}.'**
  String quoteConfirmShown(int points);

  /// No description provided for @quoteConfirmReasonAllowance.
  ///
  /// In en, this message translates to:
  /// **'The free allowance is used up for now, so this image is charged in red points instead.'**
  String get quoteConfirmReasonAllowance;

  /// No description provided for @quoteConfirmReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Prices or your account changed after the price was shown.'**
  String get quoteConfirmReasonOther;

  /// No description provided for @quoteConfirmContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue at this price'**
  String get quoteConfirmContinue;

  /// No description provided for @generationInputsActive.
  ///
  /// In en, this message translates to:
  /// **'REF {references} · VIBE {vibes}'**
  String generationInputsActive(int references, int vibes);

  /// No description provided for @generationInputsPaused.
  ///
  /// In en, this message translates to:
  /// **'{count} paused'**
  String generationInputsPaused(int count);

  /// No description provided for @generationInputsTooltip.
  ///
  /// In en, this message translates to:
  /// **'References and vibes sent with the next image. Tap to open them.'**
  String get generationInputsTooltip;

  /// No description provided for @refPausedNoRedPoints.
  ///
  /// In en, this message translates to:
  /// **'Paused: not enough red points. Not sent.'**
  String get refPausedNoRedPoints;

  /// No description provided for @refPausedNoPermission.
  ///
  /// In en, this message translates to:
  /// **'Paused: this account cannot generate with paid points. Not sent.'**
  String get refPausedNoPermission;

  /// No description provided for @refAccessCountRefs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 reference} other{{count} references}}'**
  String refAccessCountRefs(int count);

  /// No description provided for @refAccessCountVibes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 vibe} other{{count} vibes}}'**
  String refAccessCountVibes(int count);

  /// No description provided for @refAccessSeparator.
  ///
  /// In en, this message translates to:
  /// **', '**
  String get refAccessSeparator;

  /// No description provided for @refAccessPausedNoRedPoints.
  ///
  /// In en, this message translates to:
  /// **'Not enough red points: {items} paused and will not be sent'**
  String refAccessPausedNoRedPoints(String items);

  /// No description provided for @refAccessPausedNoPermission.
  ///
  /// In en, this message translates to:
  /// **'No paid generation permission: {items} paused and will not be sent'**
  String refAccessPausedNoPermission(String items);

  /// No description provided for @refAccessResumed.
  ///
  /// In en, this message translates to:
  /// **'Paid points available again: {items} will be sent again'**
  String refAccessResumed(String items);

  /// No description provided for @toolMaxRedPoints.
  ///
  /// In en, this message translates to:
  /// **'up to {points} red'**
  String toolMaxRedPoints(int points);

  /// No description provided for @generationBusy.
  ///
  /// In en, this message translates to:
  /// **'A generation is already running. Wait for it to finish.'**
  String get generationBusy;

  /// No description provided for @generationFailedFallback.
  ///
  /// In en, this message translates to:
  /// **'Generation failed'**
  String get generationFailedFallback;

  /// No description provided for @generationSeedInvalid.
  ///
  /// In en, this message translates to:
  /// **'The seed must be a whole number from 0 to 4294967295.'**
  String get generationSeedInvalid;

  /// No description provided for @generationDropToImport.
  ///
  /// In en, this message translates to:
  /// **'Drop to import settings'**
  String get generationDropToImport;

  /// No description provided for @generationCancelQueued.
  ///
  /// In en, this message translates to:
  /// **'CANCEL QUEUED'**
  String get generationCancelQueued;

  /// No description provided for @generationResumeWatching.
  ///
  /// In en, this message translates to:
  /// **'RESUME'**
  String get generationResumeWatching;

  /// No description provided for @generationWatchTimedOut.
  ///
  /// In en, this message translates to:
  /// **'Stopped waiting for the server. The images may still finish; resume to check again.'**
  String get generationWatchTimedOut;

  /// No description provided for @generationItemCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled before it started'**
  String get generationItemCancelled;

  /// No description provided for @generationReuseSeed.
  ///
  /// In en, this message translates to:
  /// **'REUSE SEED'**
  String get generationReuseSeed;

  /// No description provided for @photoshootTitle.
  ///
  /// In en, this message translates to:
  /// **'PHOTOSHOOT'**
  String get photoshootTitle;

  /// No description provided for @photoshootCharacterNotFound.
  ///
  /// In en, this message translates to:
  /// **'Character not found'**
  String get photoshootCharacterNotFound;

  /// No description provided for @photoshootNoOutfit.
  ///
  /// In en, this message translates to:
  /// **'(no outfit)'**
  String get photoshootNoOutfit;

  /// No description provided for @photoshootPreviewPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'YOUR SHOT APPEARS HERE'**
  String get photoshootPreviewPlaceholder;

  /// No description provided for @photoshootTapToView.
  ///
  /// In en, this message translates to:
  /// **'TAP TO VIEW'**
  String get photoshootTapToView;

  /// No description provided for @photoshootTabDress.
  ///
  /// In en, this message translates to:
  /// **'DRESS'**
  String get photoshootTabDress;

  /// No description provided for @photoshootTabScene.
  ///
  /// In en, this message translates to:
  /// **'SCENE'**
  String get photoshootTabScene;

  /// No description provided for @photoshootTabPrompt.
  ///
  /// In en, this message translates to:
  /// **'PROMPT'**
  String get photoshootTabPrompt;

  /// No description provided for @photoshootNoOutfitHint.
  ///
  /// In en, this message translates to:
  /// **'No outfit to dress — add one from the character editor.'**
  String get photoshootNoOutfitHint;

  /// No description provided for @photoshootSaveState.
  ///
  /// In en, this message translates to:
  /// **'SAVE STATE TO OUTFIT'**
  String get photoshootSaveState;

  /// No description provided for @photoshootOutfitStateSaved.
  ///
  /// In en, this message translates to:
  /// **'OUTFIT STATE SAVED'**
  String get photoshootOutfitStateSaved;

  /// No description provided for @photoshootSectionStyle.
  ///
  /// In en, this message translates to:
  /// **'STYLE'**
  String get photoshootSectionStyle;

  /// No description provided for @photoshootSectionPose.
  ///
  /// In en, this message translates to:
  /// **'POSE'**
  String get photoshootSectionPose;

  /// No description provided for @photoshootSectionEnvironment.
  ///
  /// In en, this message translates to:
  /// **'ENVIRONMENT'**
  String get photoshootSectionEnvironment;

  /// No description provided for @photoshootCustomPoseHint.
  ///
  /// In en, this message translates to:
  /// **'custom pose tags…'**
  String get photoshootCustomPoseHint;

  /// No description provided for @photoshootCustomEnvHint.
  ///
  /// In en, this message translates to:
  /// **'custom environment tags…'**
  String get photoshootCustomEnvHint;

  /// No description provided for @photoshootSelectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String photoshootSelectedCount(int count);

  /// No description provided for @photoshootClear.
  ///
  /// In en, this message translates to:
  /// **'CLEAR'**
  String get photoshootClear;

  /// No description provided for @photoshootNoPresets.
  ///
  /// In en, this message translates to:
  /// **'No presets available'**
  String get photoshootNoPresets;

  /// No description provided for @photoshootAssembledPrompt.
  ///
  /// In en, this message translates to:
  /// **'ASSEMBLED PROMPT'**
  String get photoshootAssembledPrompt;

  /// No description provided for @photoshootTagCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tags'**
  String photoshootTagCount(int count);

  /// No description provided for @photoshootEmptyPrompt.
  ///
  /// In en, this message translates to:
  /// **'(empty)'**
  String get photoshootEmptyPrompt;

  /// No description provided for @photoshootPromptBuiltFrom.
  ///
  /// In en, this message translates to:
  /// **'Built from: style → body → outfit → pose → environment. Adjust in the Dress and Scene tabs.'**
  String get photoshootPromptBuiltFrom;

  /// No description provided for @photoshootGenerate.
  ///
  /// In en, this message translates to:
  /// **'GENERATE'**
  String get photoshootGenerate;

  /// No description provided for @photoshootGenerating.
  ///
  /// In en, this message translates to:
  /// **'GENERATING…'**
  String get photoshootGenerating;

  /// No description provided for @photoshootSend.
  ///
  /// In en, this message translates to:
  /// **'SEND'**
  String get photoshootSend;

  /// No description provided for @photoshootSentToMain.
  ///
  /// In en, this message translates to:
  /// **'SENT TO MAIN PROMPT'**
  String get photoshootSentToMain;

  /// No description provided for @photoshootGenerated.
  ///
  /// In en, this message translates to:
  /// **'GENERATED'**
  String get photoshootGenerated;

  /// No description provided for @photoshootGenerationFailed.
  ///
  /// In en, this message translates to:
  /// **'GENERATION FAILED: {reason}'**
  String photoshootGenerationFailed(String reason);

  /// No description provided for @photoshootSelectOutfit.
  ///
  /// In en, this message translates to:
  /// **'OUTFIT'**
  String get photoshootSelectOutfit;

  /// No description provided for @photoshootStyleCharacterDefault.
  ///
  /// In en, this message translates to:
  /// **'Character default'**
  String get photoshootStyleCharacterDefault;

  /// No description provided for @photoshootStyleAnime.
  ///
  /// In en, this message translates to:
  /// **'Anime'**
  String get photoshootStyleAnime;

  /// No description provided for @photoshootStylePainterly.
  ///
  /// In en, this message translates to:
  /// **'Painterly'**
  String get photoshootStylePainterly;

  /// No description provided for @photoshootStylePhotoreal.
  ///
  /// In en, this message translates to:
  /// **'Photoreal'**
  String get photoshootStylePhotoreal;

  /// No description provided for @photoshootStyleSketch.
  ///
  /// In en, this message translates to:
  /// **'Sketch'**
  String get photoshootStyleSketch;

  /// No description provided for @photoshootStyleWatercolor.
  ///
  /// In en, this message translates to:
  /// **'Watercolour'**
  String get photoshootStyleWatercolor;

  /// No description provided for @photoshootStyleInk.
  ///
  /// In en, this message translates to:
  /// **'Ink'**
  String get photoshootStyleInk;

  /// No description provided for @cascadeHelpTitle.
  ///
  /// In en, this message translates to:
  /// **'CASCADE GUIDE'**
  String get cascadeHelpTitle;

  /// No description provided for @cascadeHelpOverviewHeader.
  ///
  /// In en, this message translates to:
  /// **'OVERVIEW'**
  String get cascadeHelpOverviewHeader;

  /// No description provided for @cascadeHelpOverviewBody.
  ///
  /// In en, this message translates to:
  /// **'Cascade generates multi-beat scene sequences with consistent characters. Each beat is one generation with its own environment, character poses, and settings. Character appearances are set once in the casting sheet and applied to all beats.'**
  String get cascadeHelpOverviewBody;

  /// No description provided for @cascadeHelpSetupHeader.
  ///
  /// In en, this message translates to:
  /// **'SETUP FLOW'**
  String get cascadeHelpSetupHeader;

  /// No description provided for @cascadeHelpStepCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get cascadeHelpStepCreate;

  /// No description provided for @cascadeHelpStepCreateDesc.
  ///
  /// In en, this message translates to:
  /// **'Set name, character count (0-5), and positioning mode'**
  String get cascadeHelpStepCreateDesc;

  /// No description provided for @cascadeHelpStepEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Beats'**
  String get cascadeHelpStepEdit;

  /// No description provided for @cascadeHelpStepEditDesc.
  ///
  /// In en, this message translates to:
  /// **'Set scene/action, environment, character prompts, actions, positions, styles, and settings per beat'**
  String get cascadeHelpStepEditDesc;

  /// No description provided for @cascadeHelpStepCast.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get cascadeHelpStepCast;

  /// No description provided for @cascadeHelpStepCastDesc.
  ///
  /// In en, this message translates to:
  /// **'Save and return to the main screen playback view'**
  String get cascadeHelpStepCastDesc;

  /// No description provided for @cascadeHelpStepGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get cascadeHelpStepGenerate;

  /// No description provided for @cascadeHelpStepGenerateDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter character appearances, optional global injection, then generate each beat'**
  String get cascadeHelpStepGenerateDesc;

  /// No description provided for @cascadeHelpBasePromptHeader.
  ///
  /// In en, this message translates to:
  /// **'BASE PROMPT'**
  String get cascadeHelpBasePromptHeader;

  /// No description provided for @cascadeHelpScene.
  ///
  /// In en, this message translates to:
  /// **'Scene / Action'**
  String get cascadeHelpScene;

  /// No description provided for @cascadeHelpSceneDesc.
  ///
  /// In en, this message translates to:
  /// **'Base-prompt tags for what is happening and how it is framed (e.g., \"2girls, hugging, wide shot, from above\"). Subject-count, action, and camera tags go here.'**
  String get cascadeHelpSceneDesc;

  /// No description provided for @cascadeHelpEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get cascadeHelpEnvironment;

  /// No description provided for @cascadeHelpEnvironmentDesc.
  ///
  /// In en, this message translates to:
  /// **'Base-prompt tags for where the scene takes place (e.g., \"forest, night, indoors\").'**
  String get cascadeHelpEnvironmentDesc;

  /// No description provided for @cascadeHelpBasePromptNote.
  ///
  /// In en, this message translates to:
  /// **'Both are tags (not prose) and feed the same base prompt — Scene / Action leads, Environment follows.'**
  String get cascadeHelpBasePromptNote;

  /// No description provided for @cascadeHelpSlotsHeader.
  ///
  /// In en, this message translates to:
  /// **'CHARACTER SLOTS'**
  String get cascadeHelpSlotsHeader;

  /// No description provided for @cascadeHelpSlotPositive.
  ///
  /// In en, this message translates to:
  /// **'Positive Prompt'**
  String get cascadeHelpSlotPositive;

  /// No description provided for @cascadeHelpSlotPositiveDesc.
  ///
  /// In en, this message translates to:
  /// **'Per-beat character tags (e.g., \"happy, sitting\")'**
  String get cascadeHelpSlotPositiveDesc;

  /// No description provided for @cascadeHelpSlotNegative.
  ///
  /// In en, this message translates to:
  /// **'Negative Prompt'**
  String get cascadeHelpSlotNegative;

  /// No description provided for @cascadeHelpSlotNegativeDesc.
  ///
  /// In en, this message translates to:
  /// **'Per-beat undesired content for this character'**
  String get cascadeHelpSlotNegativeDesc;

  /// No description provided for @cascadeHelpSlotGrid.
  ///
  /// In en, this message translates to:
  /// **'Position Grid'**
  String get cascadeHelpSlotGrid;

  /// No description provided for @cascadeHelpSlotGridDesc.
  ///
  /// In en, this message translates to:
  /// **'5x5 grid for precise placement (if manual positioning is on)'**
  String get cascadeHelpSlotGridDesc;

  /// No description provided for @cascadeHelpSlotActions.
  ///
  /// In en, this message translates to:
  /// **'Action Tags'**
  String get cascadeHelpSlotActions;

  /// No description provided for @cascadeHelpSlotActionsDesc.
  ///
  /// In en, this message translates to:
  /// **'Define interactions between characters for this beat'**
  String get cascadeHelpSlotActionsDesc;

  /// No description provided for @cascadeHelpActionsHeader.
  ///
  /// In en, this message translates to:
  /// **'ACTION INTERACTIONS'**
  String get cascadeHelpActionsHeader;

  /// No description provided for @cascadeHelpActionsIntro.
  ///
  /// In en, this message translates to:
  /// **'Tap the link icon between character slots to set an interaction for that beat.'**
  String get cascadeHelpActionsIntro;

  /// No description provided for @cascadeHelpSourceTarget.
  ///
  /// In en, this message translates to:
  /// **'Source → Target'**
  String get cascadeHelpSourceTarget;

  /// No description provided for @cascadeHelpSourceTargetDesc.
  ///
  /// In en, this message translates to:
  /// **'Directional action (e.g., A hugging B)'**
  String get cascadeHelpSourceTargetDesc;

  /// No description provided for @cascadeHelpMutual.
  ///
  /// In en, this message translates to:
  /// **'Mutual ↔'**
  String get cascadeHelpMutual;

  /// No description provided for @cascadeHelpMutualDesc.
  ///
  /// In en, this message translates to:
  /// **'Both characters participate equally (e.g., holding hands)'**
  String get cascadeHelpMutualDesc;

  /// No description provided for @cascadeHelpActionsNote.
  ///
  /// In en, this message translates to:
  /// **'Tags are embedded as source#action, target#action, or mutual#action in character prompts.'**
  String get cascadeHelpActionsNote;

  /// No description provided for @cascadeHelpCastingHeader.
  ///
  /// In en, this message translates to:
  /// **'CASTING SHEET'**
  String get cascadeHelpCastingHeader;

  /// No description provided for @cascadeHelpCastAppearance.
  ///
  /// In en, this message translates to:
  /// **'Character Appearance'**
  String get cascadeHelpCastAppearance;

  /// No description provided for @cascadeHelpCastAppearanceDesc.
  ///
  /// In en, this message translates to:
  /// **'Base look for each character (e.g., \"1girl, blue hair\") — shared across all beats'**
  String get cascadeHelpCastAppearanceDesc;

  /// No description provided for @cascadeHelpCastGlobalScene.
  ///
  /// In en, this message translates to:
  /// **'Global Scene'**
  String get cascadeHelpCastGlobalScene;

  /// No description provided for @cascadeHelpCastGlobalSceneDesc.
  ///
  /// In en, this message translates to:
  /// **'Scene/action tags applied to every beat (e.g., \"2girls, school uniform\") — leads each beat\'s own Scene / Action tags'**
  String get cascadeHelpCastGlobalSceneDesc;

  /// No description provided for @cascadeHelpCastInjection.
  ///
  /// In en, this message translates to:
  /// **'Global Injection'**
  String get cascadeHelpCastInjection;

  /// No description provided for @cascadeHelpCastInjectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Additional prompt text or style applied to every beat'**
  String get cascadeHelpCastInjectionDesc;

  /// No description provided for @cascadeHelpCastThumbs.
  ///
  /// In en, this message translates to:
  /// **'Beat Thumbnails'**
  String get cascadeHelpCastThumbs;

  /// No description provided for @cascadeHelpCastThumbsDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap to select; shows preview after generation'**
  String get cascadeHelpCastThumbsDesc;

  /// No description provided for @cascadeHelpCastCaption.
  ///
  /// In en, this message translates to:
  /// **'Narration Caption'**
  String get cascadeHelpCastCaption;

  /// No description provided for @cascadeHelpCastCaptionDesc.
  ///
  /// In en, this message translates to:
  /// **'Free-text narration shown over the beat preview (display only) — prose, not tags. Toggle with the eye icon. Not saved with the cascade.'**
  String get cascadeHelpCastCaptionDesc;

  /// No description provided for @cascadeHelpCastExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get cascadeHelpCastExport;

  /// No description provided for @cascadeHelpCastExportDesc.
  ///
  /// In en, this message translates to:
  /// **'Burn captions into a single beat PNG, or assemble all generated beats into a vertical/horizontal storyboard strip (share icon)'**
  String get cascadeHelpCastExportDesc;

  /// No description provided for @cascadeHelpCastGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get cascadeHelpCastGenerate;

  /// No description provided for @cascadeHelpCastGenerateDesc.
  ///
  /// In en, this message translates to:
  /// **'Generates selected beat, auto-advances to next'**
  String get cascadeHelpCastGenerateDesc;

  /// No description provided for @cascadeHelpPerBeatHeader.
  ///
  /// In en, this message translates to:
  /// **'PER-BEAT SETTINGS'**
  String get cascadeHelpPerBeatHeader;

  /// No description provided for @cascadeHelpPerBeatBody.
  ///
  /// In en, this message translates to:
  /// **'Each beat can have its own resolution, sampler, steps, scale, and styles. Styles are toggled per-beat from your style library.'**
  String get cascadeHelpPerBeatBody;

  /// No description provided for @cascadeHelpTipsHeader.
  ///
  /// In en, this message translates to:
  /// **'TIPS'**
  String get cascadeHelpTipsHeader;

  /// No description provided for @cascadeHelpTip1.
  ///
  /// In en, this message translates to:
  /// **'Use environment tags for scene changes between beats'**
  String get cascadeHelpTip1;

  /// No description provided for @cascadeHelpTip2.
  ///
  /// In en, this message translates to:
  /// **'Keep character appearances consistent in the casting sheet'**
  String get cascadeHelpTip2;

  /// No description provided for @cascadeHelpTip3.
  ///
  /// In en, this message translates to:
  /// **'Change action tags per-beat to show interactions evolving'**
  String get cascadeHelpTip3;

  /// No description provided for @cascadeHelpTip4.
  ///
  /// In en, this message translates to:
  /// **'Clone beats to quickly iterate on similar scenes'**
  String get cascadeHelpTip4;

  /// No description provided for @cascadeHelpTip5.
  ///
  /// In en, this message translates to:
  /// **'Each beat can use different styles for different moods'**
  String get cascadeHelpTip5;

  /// No description provided for @canvasHelpToolsHeader.
  ///
  /// In en, this message translates to:
  /// **'TOOLS'**
  String get canvasHelpToolsHeader;

  /// No description provided for @canvasHelpPaint.
  ///
  /// In en, this message translates to:
  /// **'Paint — freehand brush'**
  String get canvasHelpPaint;

  /// No description provided for @canvasHelpErase.
  ///
  /// In en, this message translates to:
  /// **'Erase — remove strokes'**
  String get canvasHelpErase;

  /// No description provided for @canvasHelpLine.
  ///
  /// In en, this message translates to:
  /// **'Line — straight line'**
  String get canvasHelpLine;

  /// No description provided for @canvasHelpRectangle.
  ///
  /// In en, this message translates to:
  /// **'Rectangle — outline or filled'**
  String get canvasHelpRectangle;

  /// No description provided for @canvasHelpCircle.
  ///
  /// In en, this message translates to:
  /// **'Circle / Ellipse'**
  String get canvasHelpCircle;

  /// No description provided for @canvasHelpFill.
  ///
  /// In en, this message translates to:
  /// **'Fill — flood fill area'**
  String get canvasHelpFill;

  /// No description provided for @canvasHelpText.
  ///
  /// In en, this message translates to:
  /// **'Text — add text to canvas'**
  String get canvasHelpText;

  /// No description provided for @canvasHelpEyedropper.
  ///
  /// In en, this message translates to:
  /// **'Eyedropper — pick color'**
  String get canvasHelpEyedropper;

  /// No description provided for @canvasHelpTransform.
  ///
  /// In en, this message translates to:
  /// **'Transform — move/scale layer'**
  String get canvasHelpTransform;

  /// No description provided for @canvasHelpSelect.
  ///
  /// In en, this message translates to:
  /// **'Select — rectangular selection'**
  String get canvasHelpSelect;

  /// No description provided for @canvasHelpLasso.
  ///
  /// In en, this message translates to:
  /// **'Lasso — freehand selection'**
  String get canvasHelpLasso;

  /// No description provided for @canvasHelpBlur.
  ///
  /// In en, this message translates to:
  /// **'Blur — Gaussian blur brush'**
  String get canvasHelpBlur;

  /// No description provided for @canvasHelpClone.
  ///
  /// In en, this message translates to:
  /// **'Clone Stamp — copy from source'**
  String get canvasHelpClone;

  /// No description provided for @canvasHelpNavigationHeader.
  ///
  /// In en, this message translates to:
  /// **'NAVIGATION'**
  String get canvasHelpNavigationHeader;

  /// No description provided for @canvasHelpKeySpaceDrag.
  ///
  /// In en, this message translates to:
  /// **'Space + drag'**
  String get canvasHelpKeySpaceDrag;

  /// No description provided for @canvasHelpPan.
  ///
  /// In en, this message translates to:
  /// **'Pan canvas'**
  String get canvasHelpPan;

  /// No description provided for @canvasHelpKeyScroll.
  ///
  /// In en, this message translates to:
  /// **'Scroll'**
  String get canvasHelpKeyScroll;

  /// No description provided for @canvasHelpZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom in / out'**
  String get canvasHelpZoom;

  /// No description provided for @canvasHelpKeyCtrlScroll.
  ///
  /// In en, this message translates to:
  /// **'Ctrl + Scroll'**
  String get canvasHelpKeyCtrlScroll;

  /// No description provided for @canvasHelpBrushSize.
  ///
  /// In en, this message translates to:
  /// **'Adjust brush size'**
  String get canvasHelpBrushSize;

  /// No description provided for @canvasHelpBrushStep.
  ///
  /// In en, this message translates to:
  /// **'Decrease / increase brush'**
  String get canvasHelpBrushStep;

  /// No description provided for @canvasHelpActionsHeader.
  ///
  /// In en, this message translates to:
  /// **'ACTIONS'**
  String get canvasHelpActionsHeader;

  /// No description provided for @canvasHelpKeyEscape.
  ///
  /// In en, this message translates to:
  /// **'Escape'**
  String get canvasHelpKeyEscape;

  /// No description provided for @canvasHelpCancelSelection.
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get canvasHelpCancelSelection;

  /// No description provided for @canvasHelpKeyAltClick.
  ///
  /// In en, this message translates to:
  /// **'Alt + click'**
  String get canvasHelpKeyAltClick;

  /// No description provided for @canvasHelpSetCloneSource.
  ///
  /// In en, this message translates to:
  /// **'Set clone stamp source'**
  String get canvasHelpSetCloneSource;

  /// No description provided for @canvasHelpModesHeader.
  ///
  /// In en, this message translates to:
  /// **'MODES'**
  String get canvasHelpModesHeader;

  /// No description provided for @canvasHelpModeSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get canvasHelpModeSelect;

  /// No description provided for @canvasHelpModeSelectDesc.
  ///
  /// In en, this message translates to:
  /// **'Rectangular selection with corner handles for move, rotate, and scale.'**
  String get canvasHelpModeSelectDesc;

  /// No description provided for @canvasHelpModeLasso.
  ///
  /// In en, this message translates to:
  /// **'Lasso'**
  String get canvasHelpModeLasso;

  /// No description provided for @canvasHelpModeLassoDesc.
  ///
  /// In en, this message translates to:
  /// **'Freehand selection path with bounding box handles.'**
  String get canvasHelpModeLassoDesc;

  /// No description provided for @canvasHelpModeBlur.
  ///
  /// In en, this message translates to:
  /// **'Blur'**
  String get canvasHelpModeBlur;

  /// No description provided for @canvasHelpModeBlurDesc.
  ///
  /// In en, this message translates to:
  /// **'Applies Gaussian blur. Adjust sigma with the size slider.'**
  String get canvasHelpModeBlurDesc;

  /// No description provided for @canvasHelpModeClone.
  ///
  /// In en, this message translates to:
  /// **'Clone Stamp'**
  String get canvasHelpModeClone;

  /// No description provided for @canvasHelpModeCloneDesc.
  ///
  /// In en, this message translates to:
  /// **'Copies pixels from a source point. Alt+click to set source, then paint.'**
  String get canvasHelpModeCloneDesc;

  /// No description provided for @canvasHelpModeSmooth.
  ///
  /// In en, this message translates to:
  /// **'Smooth'**
  String get canvasHelpModeSmooth;

  /// No description provided for @canvasHelpModeSmoothDesc.
  ///
  /// In en, this message translates to:
  /// **'Toggle in toolbar for anti-aliased brush strokes.'**
  String get canvasHelpModeSmoothDesc;

  /// No description provided for @commonApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// No description provided for @commonDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get commonDefault;

  /// No description provided for @pinUnlockButton.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get pinUnlockButton;

  /// No description provided for @pinLockoutMessage.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Try again in {seconds}s'**
  String pinLockoutMessage(int seconds);

  /// No description provided for @pinBiometricUnlock.
  ///
  /// In en, this message translates to:
  /// **'Biometric unlock'**
  String get pinBiometricUnlock;

  /// No description provided for @pinUnlockReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock NAIWeaver'**
  String get pinUnlockReason;

  /// No description provided for @jukeboxPlayerVolume.
  ///
  /// In en, this message translates to:
  /// **'PLAYER VOLUME'**
  String get jukeboxPlayerVolume;

  /// No description provided for @jukeboxCategoryCustom.
  ///
  /// In en, this message translates to:
  /// **'CUSTOM'**
  String get jukeboxCategoryCustom;

  /// No description provided for @galleryShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Share failed: {error}'**
  String galleryShareFailed(String error);

  /// No description provided for @gallerySdCard.
  ///
  /// In en, this message translates to:
  /// **'SD card'**
  String get gallerySdCard;

  /// No description provided for @canvasQuick.
  ///
  /// In en, this message translates to:
  /// **'QUICK'**
  String get canvasQuick;

  /// No description provided for @canvasReset.
  ///
  /// In en, this message translates to:
  /// **'RESET'**
  String get canvasReset;

  /// No description provided for @canvasPalette.
  ///
  /// In en, this message translates to:
  /// **'PALETTE'**
  String get canvasPalette;

  /// No description provided for @canvasRecent.
  ///
  /// In en, this message translates to:
  /// **'RECENT'**
  String get canvasRecent;

  /// No description provided for @canvasResizeTitle.
  ///
  /// In en, this message translates to:
  /// **'RESIZE CANVAS'**
  String get canvasResizeTitle;

  /// No description provided for @canvasAnchor.
  ///
  /// In en, this message translates to:
  /// **'ANCHOR'**
  String get canvasAnchor;

  /// No description provided for @helpShortcutKeyHoldTap.
  ///
  /// In en, this message translates to:
  /// **'Hold tap'**
  String get helpShortcutKeyHoldTap;

  /// No description provided for @helpShortcutKeyDragDrop.
  ///
  /// In en, this message translates to:
  /// **'Drag & drop PNG'**
  String get helpShortcutKeyDragDrop;

  /// No description provided for @charsDress.
  ///
  /// In en, this message translates to:
  /// **'dress'**
  String get charsDress;

  /// No description provided for @tagSuggestHonorOutfitState.
  ///
  /// In en, this message translates to:
  /// **'honor outfit state'**
  String get tagSuggestHonorOutfitState;

  /// No description provided for @charEditorSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'CHARACTER {n} EDITOR'**
  String charEditorSheetTitle(int n);

  /// No description provided for @charEditorNameOptional.
  ///
  /// In en, this message translates to:
  /// **'NAME (OPTIONAL)'**
  String get charEditorNameOptional;

  /// No description provided for @charEditorCharacterPrompt.
  ///
  /// In en, this message translates to:
  /// **'CHARACTER PROMPT'**
  String get charEditorCharacterPrompt;

  /// No description provided for @charEditorEnterTags.
  ///
  /// In en, this message translates to:
  /// **'ENTER TAGS'**
  String get charEditorEnterTags;

  /// No description provided for @charEditorCharacterUc.
  ///
  /// In en, this message translates to:
  /// **'CHARACTER UC'**
  String get charEditorCharacterUc;

  /// No description provided for @charEditorPositionGrid.
  ///
  /// In en, this message translates to:
  /// **'POSITION (5x5 GRID)'**
  String get charEditorPositionGrid;

  /// No description provided for @charEditorSaveCharacter.
  ///
  /// In en, this message translates to:
  /// **'SAVE CHARACTER'**
  String get charEditorSaveCharacter;

  /// No description provided for @interactionEditorTitle.
  ///
  /// In en, this message translates to:
  /// **'INTERACTION EDITOR'**
  String get interactionEditorTitle;

  /// No description provided for @interactionActionLabel.
  ///
  /// In en, this message translates to:
  /// **'ACTION'**
  String get interactionActionLabel;

  /// No description provided for @interactionActionHint.
  ///
  /// In en, this message translates to:
  /// **'ENTER ACTION (e.g., hugging)'**
  String get interactionActionHint;

  /// No description provided for @interactionDirectionLabel.
  ///
  /// In en, this message translates to:
  /// **'DIRECTION'**
  String get interactionDirectionLabel;

  /// No description provided for @interactionSave.
  ///
  /// In en, this message translates to:
  /// **'SAVE INTERACTION'**
  String get interactionSave;

  /// No description provided for @tagLibPreviewSummary.
  ///
  /// In en, this message translates to:
  /// **'P: {prompt} | {width}X{height} | STEPS: {steps} | SCALE: {scale}'**
  String tagLibPreviewSummary(
    String prompt,
    int width,
    int height,
    int steps,
    String scale,
  );

  /// No description provided for @panelSectionError.
  ///
  /// In en, this message translates to:
  /// **'Error in {id}: {error}'**
  String panelSectionError(String id, String error);

  /// No description provided for @mlStageStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting...'**
  String get mlStageStarting;

  /// No description provided for @mlStagePreprocessing.
  ///
  /// In en, this message translates to:
  /// **'Preprocessing...'**
  String get mlStagePreprocessing;

  /// No description provided for @mlStageAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing image...'**
  String get mlStageAnalyzing;

  /// No description provided for @mlStageLoadingModel.
  ///
  /// In en, this message translates to:
  /// **'Loading model...'**
  String get mlStageLoadingModel;

  /// No description provided for @mlStageLoadingEncoder.
  ///
  /// In en, this message translates to:
  /// **'Loading encoder...'**
  String get mlStageLoadingEncoder;

  /// No description provided for @mlStageEncodingImage.
  ///
  /// In en, this message translates to:
  /// **'Encoding image...'**
  String get mlStageEncodingImage;

  /// No description provided for @mlStageRunningInference.
  ///
  /// In en, this message translates to:
  /// **'Running inference...'**
  String get mlStageRunningInference;

  /// No description provided for @mlStageGeneratingMatte.
  ///
  /// In en, this message translates to:
  /// **'Generating matte...'**
  String get mlStageGeneratingMatte;

  /// No description provided for @mlStageGeneratingMask.
  ///
  /// In en, this message translates to:
  /// **'Generating mask...'**
  String get mlStageGeneratingMask;

  /// No description provided for @mlStageApplyingMask.
  ///
  /// In en, this message translates to:
  /// **'Applying mask...'**
  String get mlStageApplyingMask;

  /// No description provided for @mlStageSplittingTiles.
  ///
  /// In en, this message translates to:
  /// **'Splitting into tiles...'**
  String get mlStageSplittingTiles;

  /// No description provided for @mlStageUpscalingTiles.
  ///
  /// In en, this message translates to:
  /// **'Upscaling tiles...'**
  String get mlStageUpscalingTiles;

  /// No description provided for @mlStageRecombiningAlpha.
  ///
  /// In en, this message translates to:
  /// **'Recombining alpha...'**
  String get mlStageRecombiningAlpha;

  /// No description provided for @mlStageStitching.
  ///
  /// In en, this message translates to:
  /// **'Stitching result...'**
  String get mlStageStitching;

  /// No description provided for @mlStageComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get mlStageComplete;

  /// No description provided for @mlCpuOnly.
  ///
  /// In en, this message translates to:
  /// **'CPU only'**
  String get mlCpuOnly;

  /// No description provided for @mlSegmentEncodeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to encode image — check that segmentation models are downloaded'**
  String get mlSegmentEncodeFailed;

  /// No description provided for @mlSegmentNotEncoded.
  ///
  /// In en, this message translates to:
  /// **'Image not encoded — try re-opening the segment tool'**
  String get mlSegmentNotEncoded;

  /// No description provided for @mlSegmentFailed.
  ///
  /// In en, this message translates to:
  /// **'Segmentation failed — try different points'**
  String get mlSegmentFailed;

  /// No description provided for @charsGenStepCreating.
  ///
  /// In en, this message translates to:
  /// **'Creating character…'**
  String get charsGenStepCreating;

  /// No description provided for @charsGenStepWardrobe.
  ///
  /// In en, this message translates to:
  /// **'Generating wardrobe…'**
  String get charsGenStepWardrobe;

  /// No description provided for @charsGenStepSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get charsGenStepSaving;

  /// No description provided for @charsGenStepDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get charsGenStepDone;

  /// No description provided for @charsGenErrUnusable.
  ///
  /// In en, this message translates to:
  /// **'The model didn\'t return usable character JSON. Try again, or pick a higher-tier account / larger output length.'**
  String get charsGenErrUnusable;

  /// No description provided for @canvasLayerNameN.
  ///
  /// In en, this message translates to:
  /// **'Layer {n}'**
  String canvasLayerNameN(int n);

  /// No description provided for @canvasImageLayerNameN.
  ///
  /// In en, this message translates to:
  /// **'Image {n}'**
  String canvasImageLayerNameN(int n);

  /// No description provided for @canvasLayerCopyName.
  ///
  /// In en, this message translates to:
  /// **'{name} copy'**
  String canvasLayerCopyName(String name);

  /// No description provided for @canvasSegmentedLayerName.
  ///
  /// In en, this message translates to:
  /// **'Segmented'**
  String get canvasSegmentedLayerName;

  /// No description provided for @commonCopyName.
  ///
  /// In en, this message translates to:
  /// **'{name} (Copy)'**
  String commonCopyName(String name);

  /// No description provided for @packDefaultExportName.
  ///
  /// In en, this message translates to:
  /// **'My Pack'**
  String get packDefaultExportName;

  /// No description provided for @slideshowDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Slideshow {n}'**
  String slideshowDefaultName(int n);

  /// No description provided for @mlModelDescIsnetAnime.
  ///
  /// In en, this message translates to:
  /// **'Binary mask, anime-optimized'**
  String get mlModelDescIsnetAnime;

  /// No description provided for @mlModelDescRmbgQuantized.
  ///
  /// In en, this message translates to:
  /// **'Alpha matte, quantized'**
  String get mlModelDescRmbgQuantized;

  /// No description provided for @mlModelDescRmbgBest.
  ///
  /// In en, this message translates to:
  /// **'Alpha matte, best quality'**
  String get mlModelDescRmbgBest;

  /// No description provided for @mlModelDescUpscaleFast.
  ///
  /// In en, this message translates to:
  /// **'2x upscaling, fast and tiny'**
  String get mlModelDescUpscaleFast;

  /// No description provided for @mlModelDescUpscaleMobile.
  ///
  /// In en, this message translates to:
  /// **'2x upscaling, mobile fallback'**
  String get mlModelDescUpscaleMobile;

  /// No description provided for @mlModelDescUpscaleBest.
  ///
  /// In en, this message translates to:
  /// **'2x upscaling, best quality'**
  String get mlModelDescUpscaleBest;

  /// No description provided for @mlModelDescSamEncoder.
  ///
  /// In en, this message translates to:
  /// **'Image encoder for interactive segmentation'**
  String get mlModelDescSamEncoder;

  /// No description provided for @mlModelDescSamDecoder.
  ///
  /// In en, this message translates to:
  /// **'Mask decoder for interactive segmentation'**
  String get mlModelDescSamDecoder;

  /// No description provided for @soundfontDescNes.
  ///
  /// In en, this message translates to:
  /// **'8-bit retro NES sounds'**
  String get soundfontDescNes;

  /// No description provided for @soundfontDescGeneralUser.
  ///
  /// In en, this message translates to:
  /// **'High quality General MIDI soundfont'**
  String get soundfontDescGeneralUser;

  /// No description provided for @soundfontDescCat.
  ///
  /// In en, this message translates to:
  /// **'Every instrument is a meowing cat'**
  String get soundfontDescCat;

  /// No description provided for @soundfontDescSnes.
  ///
  /// In en, this message translates to:
  /// **'16-bit Super Nintendo sounds'**
  String get soundfontDescSnes;

  /// No description provided for @soundfontDescGenesis.
  ///
  /// In en, this message translates to:
  /// **'Sega Genesis YM2612 FM synth'**
  String get soundfontDescGenesis;

  /// No description provided for @soundfontDescN64Roxie.
  ///
  /// In en, this message translates to:
  /// **'Nintendo 64 game samples'**
  String get soundfontDescN64Roxie;

  /// No description provided for @soundfontDescN64Sdk.
  ///
  /// In en, this message translates to:
  /// **'Nintendo 64 SDK default samples'**
  String get soundfontDescN64Sdk;

  /// No description provided for @mlDownloadHashMismatch.
  ///
  /// In en, this message translates to:
  /// **'Hash verification failed'**
  String get mlDownloadHashMismatch;

  /// Title of the screen shown when app start-up fails.
  ///
  /// In en, this message translates to:
  /// **'NAIWeaver could not start'**
  String get startupFailedTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
