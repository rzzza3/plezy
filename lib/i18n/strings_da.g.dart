///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsDa extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsDa({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.da,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver) {
		super.$meta.setFlatMapFunction($meta.getTranslation); // copy base translations to super.$meta
		$meta.setFlatMapFunction(_flatMapFunction);
	}

	/// Metadata for the translations of <da>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	/// Access flat map
	@override dynamic operator[](String key) => $meta.getTranslation(key) ?? super.$meta.getTranslation(key);

	late final TranslationsDa _root = this; // ignore: unused_field

	@override 
	TranslationsDa $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsDa(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$app$da app = _Translations$app$da._(_root);
	@override late final _Translations$auth$da auth = _Translations$auth$da._(_root);
	@override late final _Translations$common$da common = _Translations$common$da._(_root);
	@override late final _Translations$screens$da screens = _Translations$screens$da._(_root);
	@override late final _Translations$update$da update = _Translations$update$da._(_root);
	@override late final _Translations$settings$da settings = _Translations$settings$da._(_root);
	@override late final _Translations$search$da search = _Translations$search$da._(_root);
	@override late final _Translations$hotkeys$da hotkeys = _Translations$hotkeys$da._(_root);
	@override late final _Translations$fileInfo$da fileInfo = _Translations$fileInfo$da._(_root);
	@override late final _Translations$mediaMenu$da mediaMenu = _Translations$mediaMenu$da._(_root);
	@override late final _Translations$rateSheet$da rateSheet = _Translations$rateSheet$da._(_root);
	@override late final _Translations$accessibility$da accessibility = _Translations$accessibility$da._(_root);
	@override late final _Translations$tooltips$da tooltips = _Translations$tooltips$da._(_root);
	@override late final _Translations$audioTracks$da audioTracks = _Translations$audioTracks$da._(_root);
	@override late final _Translations$videoControls$da videoControls = _Translations$videoControls$da._(_root);
	@override late final _Translations$messages$da messages = _Translations$messages$da._(_root);
	@override late final _Translations$subtitlingStyling$da subtitlingStyling = _Translations$subtitlingStyling$da._(_root);
	@override late final _Translations$mpvConfig$da mpvConfig = _Translations$mpvConfig$da._(_root);
	@override late final _Translations$profiles$da profiles = _Translations$profiles$da._(_root);
	@override late final _Translations$connections$da connections = _Translations$connections$da._(_root);
	@override late final _Translations$accountPreferences$da accountPreferences = _Translations$accountPreferences$da._(_root);
	@override late final _Translations$discover$da discover = _Translations$discover$da._(_root);
	@override late final _Translations$errors$da errors = _Translations$errors$da._(_root);
	@override late final _Translations$libraries$da libraries = _Translations$libraries$da._(_root);
	@override late final _Translations$about$da about = _Translations$about$da._(_root);
	@override late final _Translations$hubDetail$da hubDetail = _Translations$hubDetail$da._(_root);
	@override late final _Translations$logs$da logs = _Translations$logs$da._(_root);
	@override late final _Translations$startup$da startup = _Translations$startup$da._(_root);
	@override late final _Translations$licenses$da licenses = _Translations$licenses$da._(_root);
	@override late final _Translations$navigation$da navigation = _Translations$navigation$da._(_root);
	@override late final _Translations$explore$da explore = _Translations$explore$da._(_root);
	@override late final _Translations$liveTv$da liveTv = _Translations$liveTv$da._(_root);
	@override late final _Translations$collections$da collections = _Translations$collections$da._(_root);
	@override late final _Translations$playlists$da playlists = _Translations$playlists$da._(_root);
	@override late final _Translations$music$da music = _Translations$music$da._(_root);
	@override late final _Translations$watchTogether$da watchTogether = _Translations$watchTogether$da._(_root);
	@override late final _Translations$downloads$da downloads = _Translations$downloads$da._(_root);
	@override late final _Translations$shaders$da shaders = _Translations$shaders$da._(_root);
	@override late final _Translations$companionRemote$da companionRemote = _Translations$companionRemote$da._(_root);
	@override late final _Translations$videoSettings$da videoSettings = _Translations$videoSettings$da._(_root);
	@override late final _Translations$performanceOverlay$da performanceOverlay = _Translations$performanceOverlay$da._(_root);
	@override late final _Translations$externalPlayer$da externalPlayer = _Translations$externalPlayer$da._(_root);
	@override late final _Translations$metadataEdit$da metadataEdit = _Translations$metadataEdit$da._(_root);
	@override late final _Translations$matchScreen$da matchScreen = _Translations$matchScreen$da._(_root);
	@override late final _Translations$serverTasks$da serverTasks = _Translations$serverTasks$da._(_root);
	@override late final _Translations$trakt$da trakt = _Translations$trakt$da._(_root);
	@override late final _Translations$seerr$da seerr = _Translations$seerr$da._(_root);
	@override late final _Translations$services$da services = _Translations$services$da._(_root);
	@override late final _Translations$addServer$da addServer = _Translations$addServer$da._(_root);
}

// Path: app
class _Translations$app$da extends Translations$app$en {
	_Translations$app$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Plezy';
}

// Path: auth
class _Translations$auth$da extends Translations$auth$en {
	_Translations$auth$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get localDataRecoveryRequired => 'Plezy kunne ikke gendanne lokale loginoplysninger og ventende afspilningsdata på en sikker måde. Log ind igen.';
}

// Path: common
class _Translations$common$da extends Translations$common$en {
	_Translations$common$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get cancel => 'Annuller';
	@override String get save => 'Gem';
	@override String get close => 'Luk';
	@override String get clear => 'Ryd';
	@override String get reset => 'Nulstil';
	@override String get later => 'Senere';
	@override String get submit => 'Indsend';
	@override String get retry => 'Prøv igen';
	@override String get logout => 'Log ud';
	@override String get unknown => 'Ukendt';
	@override String get refresh => 'Opdater';
	@override String get yes => 'Ja';
	@override String get no => 'Nej';
	@override String get delete => 'Slet';
	@override String get edit => 'Rediger';
	@override String get shuffle => 'Bland';
	@override String get addTo => 'Tilføj til...';
	@override String get createNew => 'Opret ny';
	@override String get connect => 'Forbind';
	@override String get disconnect => 'Afbryd';
	@override String get play => 'Afspil';
	@override String get pause => 'Pause';
	@override String get resume => 'Genoptag';
	@override String get error => 'Fejl';
	@override String get search => 'Søg';
	@override String get home => 'Hjem';
	@override String get back => 'Tilbage';
	@override String get settings => 'Indstillinger';
	@override String get mute => 'Lydløs';
	@override String get ok => 'OK';
	@override String get off => 'Fra';
	@override String get options => 'Valgmuligheder';
	@override String seasonNumber({required Object number}) => 'Sæson ${number}';
	@override String episodeNumberTitle({required Object number, required Object title}) => 'Episode ${number} – ${title}';
	@override String chapterNumber({required Object number}) => 'Kapitel ${number}';
	@override String get reconnect => 'Genopret forbindelse';
	@override String get viewAll => 'Vis alle';
	@override String get checkingNetwork => 'Tjekker netværk...';
	@override String get loadingServers => 'Indlæser servere...';
	@override String get connectingToServers => 'Forbinder til servere...';
	@override String get startingOfflineMode => 'Starter offlinetilstand...';
	@override String get loading => 'Indlæser...';
	@override String get fullscreen => 'Fuldskærm';
	@override String get exitFullscreen => 'Forlad fuldskærm';
	@override String get pressBackAgainToExit => 'Tryk på tilbage igen for at afslutte';
	@override late final _Translations$common$ratingSource$da ratingSource = _Translations$common$ratingSource$da._(_root);
	@override String get notAvailable => 'N/A';
	@override String get url => 'URL';
	@override String get letterKeys => 'ABC';
	@override late final _Translations$common$mediaKind$da mediaKind = _Translations$common$mediaKind$da._(_root);
}

// Path: screens
class _Translations$screens$da extends Translations$screens$en {
	_Translations$screens$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get licenses => 'Licenser';
	@override String get switchProfile => 'Skift profil';
	@override String get subtitleStyling => 'Undertekststil';
	@override String get mpvConfig => 'mpv.conf';
	@override String get logs => 'Logfiler';
}

// Path: update
class _Translations$update$da extends Translations$update$en {
	_Translations$update$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get available => 'Opdatering tilgængelig';
	@override String versionAvailable({required Object version}) => 'Version ${version} er tilgængelig';
	@override String currentVersion({required Object version}) => 'Nuværende: ${version}';
	@override String get skipVersion => 'Spring denne version over';
	@override String get viewRelease => 'Vis udgivelse';
	@override String get latestVersion => 'Du har den nyeste version';
	@override String get checkFailed => 'Kunne ikke søge efter opdateringer';
}

// Path: settings
class _Translations$settings$da extends Translations$settings$en {
	_Translations$settings$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Indstillinger';
	@override String get supportDeveloper => 'Støt Plezy';
	@override String get supportDeveloperDescription => 'Doner via Liberapay for at finansiere udviklingen';
	@override String get language => 'Sprog';
	@override String get theme => 'Tema';
	@override String get appearance => 'Udseende';
	@override String get videoPlayback => 'Videoafspilning';
	@override String get videoPlaybackDescription => 'Konfigurer afspilningsadfærd';
	@override String get advanced => 'Avanceret';
	@override String get episodePosterMode => 'Episodeplakatstil';
	@override String get seriesPoster => 'Serieplakat';
	@override String get seasonPoster => 'Sæsonplakat';
	@override String get episodeThumbnail => 'Miniature';
	@override String get showHeroSectionDescription => 'Vis karrusel med udvalgt indhold på startskærmen';
	@override String get secondsLabel => 'Sekunder';
	@override String get minutesLabel => 'Minutter';
	@override String get secondsShort => 's';
	@override String get minutesShort => 'm';
	@override String durationHint({required Object min, required Object max}) => 'Indtast varighed (${min}-${max})';
	@override String get systemTheme => 'System';
	@override String get lightTheme => 'Lys';
	@override String get darkTheme => 'Mørk';
	@override String get oledTheme => 'OLED';
	@override String get libraryDensity => 'Bibliotekstæthed';
	@override String get displayScale => 'Skalering';
	@override String get compact => 'Kompakt';
	@override String get comfortable => 'Komfortabel';
	@override String get gridSpacing => 'Gitterafstand';
	@override String get gridSpacingTight => 'Tæt';
	@override String get gridSpacingNormal => 'Normal';
	@override String get gridSpacingSpacious => 'Rummelig';
	@override String get tvCornerSpotlightBackdrop => 'Fremhævet baggrundsbillede i hjørnet';
	@override String get tvCornerSpotlightBackdropDescription => 'Vis fremhævet grafik i øverste højre hjørne i stedet for at fylde skærmen';
	@override String get viewMode => 'Visningstilstand';
	@override String get gridView => 'Gitter';
	@override String get listView => 'Liste';
	@override String get showHeroSection => 'Vis udvalgt indhold';
	@override String get continueWatchingAction => 'Handling for "Fortsæt med at se"';
	@override String get continueWatchingPlay => 'Afspil';
	@override String get continueWatchingDetails => 'Åbn detaljer';
	@override String get episodeAction => 'Handling for afsnit';
	@override String get episodePlay => 'Afspil';
	@override String get episodeDetails => 'Åbn detaljer';
	@override String get useGlobalHubs => 'Brug startlayout';
	@override String get useGlobalHubsDescription => 'Vis samlet startsideindhold. Brug ellers biblioteksanbefalinger.';
	@override String get showServerNameOnHubs => 'Vis servernavn på hubber';
	@override String get showServerNameOnHubsDescription => 'Vis altid servernavne i titler på hubber.';
	@override String get groupLibrariesByServer => 'Grupper biblioteker efter server';
	@override String get groupLibrariesByServerDescription => 'Gruppér bibliotekerne i sidepanelet under hver medieserver.';
	@override String get alwaysKeepSidebarOpen => 'Hold altid sidepanelet åbent';
	@override String get alwaysKeepSidebarOpenDescription => 'Sidepanelet forbliver udvidet, og indholdsområdet tilpasser sig';
	@override String get showUnwatchedCount => 'Vis antal usete';
	@override String get showUnwatchedCountDescription => 'Vis antal usete episoder på serier og sæsoner';
	@override String get showWatchedIndicators => 'Vis set-markeringer';
	@override String get showWatchedIndicatorsDescription => 'Vis et flueben på sete film, serier og episoder';
	@override String get showEpisodeNumberOnCards => 'Vis episodenummer på kort';
	@override String get showEpisodeNumberOnCardsDescription => 'Vis sæson- og episodenummer på episodekort';
	@override String get showSeasonPostersOnTabs => 'Vis sæsonplakater på faner';
	@override String get showSeasonPostersOnTabsDescription => 'Vis hver sæsons plakat over dens fane';
	@override String get tvFullCardLayout => 'TV-kort med billeder over hele fladen';
	@override String get tvFullCardLayoutDescription => 'Brug TV-kort, der kun viser billeder, med skuespillernavnene ovenpå';
	@override String get focusGlow => 'Fokusglød';
	@override String get focusGlowDescription => 'Vis en blød glød omkring det fokuserede kort';
	@override String get visualEffects => 'Visuelle effekter';
	@override String get visualEffectsAuto => 'Automatisk';
	@override String get visualEffectsAutoDescription => 'Reducer automatisk effekter på enheder med lav ydeevne';
	@override String get visualEffectsFull => 'Fuld';
	@override String get visualEffectsReduced => 'Reduceret';
	@override String get visualEffectsReducedDescription => 'Færre animationer og illustrationer i lavere opløsning';
	@override String get hideSpoilers => 'Skjul spoilere for usete episoder';
	@override String get hideSpoilersDescription => 'Slør miniaturebilleder og beskrivelser for usete episoder';
	@override String get playerBackend => 'Afspillermotor';
	@override String get exoPlayer => 'ExoPlayer';
	@override String get mpv => 'mpv';
	@override String get hardwareDecoding => 'Hardwaredekodning';
	@override String get hardwareDecodingDescription => 'Brug hardwareacceleration, når den er tilgængelig';
	@override String get playbackBuffer => 'Afspilningsbuffer';
	@override String get playbackBufferAuto => 'Auto (anbefalet)';
	@override String get playbackBufferLarge => 'Stor';
	@override String get playbackBufferExtraLarge => 'Ekstra stor';
	@override String get playbackBufferDescription => 'Bufrer mere mod ustabile forbindelser. Begrænses også af bufferstørrelsen.';
	@override String get defaultQualityTitle => 'Standardkvalitet';
	@override String get cellularQualityTitle => 'Standardkvalitet på mobildata';
	@override String get cellularQualitySameAsDefault => 'Samme som standardkvalitet';
	@override String get directPlayCoveredQuality => 'Afspil mindre videoer i original kvalitet';
	@override String get directPlayCoveredQualityDescription => 'Afspil videoer, der allerede er inden for kvalitetsgrænsen, direkte i stedet for at transkode dem';
	@override String get videoCodecs => 'Videocodecs';
	@override String get videoCodecsDescription => 'Codecs uden flueben transkodes af serveren';
	@override String get videoCodecsAlwaysAccepted => 'Accepteres altid';
	@override String get musicQualityTitle => 'Musikkvalitet';
	@override String get subtitleStyling => 'Undertekststil';
	@override String get subtitleStylingDescription => 'Tilpas underteksters udseende';
	@override String get smallSkipDuration => 'Kort spring';
	@override String get largeSkipDuration => 'Langt spring';
	@override String get rewindOnResume => 'Spol tilbage ved genoptagelse';
	@override String secondsUnit({required Object seconds}) => '${seconds} sekunder';
	@override String get defaultSleepTimer => 'Standard-sovetimer';
	@override String minutesUnit({required Object minutes}) => '${minutes} minutter';
	@override String get rememberTrackSelections => 'Husk sporvalg for hver serie/film';
	@override String get rememberTrackSelectionsDescription => 'Husk valget af lyd og undertekster for hver titel';
	@override String get followServerTrackSelections => 'Brug serverens sporvalg for hvert afsnit';
	@override String get followServerTrackSelectionsDescription => 'Ved afsnitsskift anvendes lyden og underteksterne valgt på serveren i stedet for at videreføre det aktuelle valg';
	@override String get resumeMusicOnLaunch => 'Husk musiksession';
	@override String get resumeMusicOnLaunchDescription => 'Åbn den seneste sang på pause der, hvor den slap, når appen starter';
	@override String get showChapterMarkersOnTimeline => 'Vis kapitelmarkører på tidslinjen';
	@override String get showChapterMarkersOnTimelineDescription => 'Opdel tidslinjen ved kapitelgrænser';
	@override String get specialsOrdering => 'Specialafsnit i episoderekkefølge';
	@override String get specialsOrderingDescription => 'Hvor specialafsnit afspilles i seriens visningsrækkefølge';
	@override String get specialsOrderingServer => 'Følg serverrækkefølgen';
	@override String get specialsOrderingAirDate => 'Indflet efter udsendelsesdato';
	@override String get specialsOrderingLast => 'Efter almindelige sæsoner';
	@override String get clickVideoTogglesPlayback => 'Klik på videoen for at skifte mellem afspilning og pause';
	@override String get clickVideoTogglesPlaybackDescription => 'Klik på videoen for at afspille eller sætte på pause i stedet for at vise betjeningsknapperne.';
	@override String get videoPlayerControls => 'Videoafspillerkontroller';
	@override String get keyboardShortcuts => 'Tastaturgenveje';
	@override String get keyboardShortcutsDescription => 'Tilpas tastaturgenveje';
	@override String get videoPlayerNavigation => 'Videoafspillernavigation';
	@override String get videoPlayerNavigationDescription => 'Brug piletaster til at navigere videoafspillerkontroller';
	@override String get watchTogetherRelay => 'Relayserver til Se sammen';
	@override String get watchTogetherRelayDescription => 'Angiv en brugerdefineret relayserver. Alle skal bruge den samme server.';
	@override String get watchTogetherRelayHint => 'https://min-relay.eksempel.dk';
	@override String get watchTogetherRelayInvalid => 'Angiv en gyldig basis-URL til en HTTP- eller HTTPS-relayserver.';
	@override String get crashReporting => 'Fejlrapportering';
	@override String get crashReportingDescription => 'Send fejlrapporter for at hjælpe med at forbedre appen';
	@override String get debugLogging => 'Fejlfindingslogning';
	@override String get debugLoggingDescription => 'Aktiver detaljeret logning til fejlfinding';
	@override String get viewLogs => 'Vis logfiler';
	@override String get viewLogsDescription => 'Vis programmets logfiler';
	@override String get clearImageCache => 'Ryd billedcache';
	@override String get clearImageCacheDescription => 'Ryd cachelagrede covers og thumbnails. Billeder kan indlæse langsommere, indtil de downloades igen.';
	@override String get clearImageCacheSuccess => 'Billedcachen er ryddet';
	@override String get resetSettings => 'Nulstil indstillinger';
	@override String get resetSettingsDescription => 'Gendan standardindstillinger. Dette kan ikke fortrydes.';
	@override String get resetSettingsSuccess => 'Indstillinger nulstillet';
	@override String get backup => 'Sikkerhedskopi';
	@override String get exportSettings => 'Eksportér indstillinger';
	@override String get exportSettingsDescription => 'Gem dine præferencer i en fil';
	@override String get exportSettingsSuccess => 'Indstillinger eksporteret';
	@override String get importSettings => 'Importér indstillinger';
	@override String get importSettingsDescription => 'Gendan præferencer fra en fil';
	@override String get importSettingsConfirm => 'Dette vil erstatte dine nuværende indstillinger. Fortsæt?';
	@override String get importSettingsSuccess => 'Indstillinger importeret';
	@override String get importSettingsInvalidFile => 'Denne fil er ikke en gyldig eksport af Plezy-indstillinger';
	@override String get importSettingsNoUser => 'Log ind før import af indstillinger';
	@override String get shortcutsReset => 'Genveje nulstillet til standard';
	@override String get about => 'Om';
	@override String get aboutDescription => 'App-information og licenser';
	@override String get updates => 'Opdateringer';
	@override String get updateAvailable => 'Opdatering tilgængelig';
	@override String get checkForUpdates => 'Søg efter opdateringer';
	@override String get autoCheckUpdatesOnStartup => 'Søg automatisk efter opdateringer ved opstart';
	@override String get autoCheckUpdatesOnStartupDescription => 'Giv besked, når en opdatering er tilgængelig ved start';
	@override String get validationErrorEnterNumber => 'Indtast et gyldigt tal';
	@override String validationErrorDuration({required Object min, required Object max, required Object unit}) => 'Varigheden skal være mellem ${min} og ${max} ${unit}';
	@override String shortcutAlreadyAssigned({required Object action}) => 'Genvejen er allerede tildelt ${action}';
	@override String shortcutUpdated({required Object action}) => 'Genvejen for ${action} er opdateret';
	@override String get saveFailed => 'Ændringerne kunne ikke gemmes. Prøv igen.';
	@override String get autoPlayAndSkip => 'Autoafspilning og spring';
	@override String get autoPlayNextEpisode => 'Autoafspil næste afsnit';
	@override String get autoPlayNextEpisodeDescription => 'Start automatisk næste afsnit, når et afsnit slutter';
	@override String get shuffleStartsFromBeginning => 'Blandet afspilning starter forfra';
	@override String get shuffleStartsFromBeginningDescription => 'Start hvert afsnit forfra ved blandet afspilning i stedet for at genoptage';
	@override String get playNextCountdown => 'Nedtælling til næste afsnit';
	@override String get playNextCountdownImmediate => 'Afspil med det samme';
	@override String get skipIntroMode => 'Spring intro over';
	@override String get skipIntroModeOffDescription => 'Afspil introer normalt uden en spring-knap';
	@override String get skipIntroModeButtonDescription => 'Vis en spring-knap, når en intro starter';
	@override String get skipIntroModeAutoDescription => 'Spring introer automatisk over efter forsinkelsen nedenfor';
	@override String get skipCreditsMode => 'Spring rulletekster over';
	@override String get skipCreditsModeOffDescription => 'Afspil rulletekster normalt uden en spring-knap';
	@override String get skipCreditsModeButtonDescription => 'Vis en spring-knap, når rulleteksterne starter';
	@override String get skipCreditsModeAutoDescription => 'Spring rulletekster automatisk over, og afspil næste afsnit';
	@override String get skipMarkerModeOff => 'Fra';
	@override String get skipMarkerModeButton => 'Vis knap';
	@override String get skipMarkerModeAuto => 'Automatisk';
	@override String get forceSkipMarkerFallback => 'Tving reservemarkører';
	@override String get autoSkipDelay => 'Forsinkelse ved automatisk spring';
	@override String autoSkipDelayDescription({required Object seconds}) => 'Vent ${seconds} sekunder, før der springes automatisk';
	@override String get introPattern => 'Intromarkørmønster';
	@override String get introPatternDescription => 'Regulært udtryk til at genkende intromarkører i kapiteltitler';
	@override String get creditsPattern => 'Rulletekstmarkørmønster';
	@override String get creditsPatternDescription => 'Regulært udtryk til at genkende rulletekstmarkører i kapiteltitler';
	@override String get invalidRegex => 'Ugyldigt regulært udtryk';
	@override String get regex => 'Regulært udtryk';
	@override String get downloads => 'Downloads';
	@override String get downloadLocationDescription => 'Vælg, hvor downloadet indhold skal gemmes';
	@override String get downloadLocationDefault => 'Standard (applager)';
	@override String get downloadLocationCustom => 'Brugerdefineret placering';
	@override String get selectFolder => 'Vælg mappe';
	@override String get resetToDefault => 'Nulstil til standard';
	@override String currentPath({required Object path}) => 'Nuværende: ${path}';
	@override String get downloadLocationChanged => 'Downloadplacering ændret';
	@override String get downloadLocationReset => 'Downloadplacering nulstillet';
	@override String get downloadLocationInvalid => 'Valgt mappe er ikke skrivbar';
	@override String get downloadLocationPickerUnavailable => 'Mappevalg er ikke tilgængeligt på denne enhed';
	@override String get downloadOnWifiOnly => 'Download kun via Wi-Fi';
	@override String get downloadOnWifiOnlyDescription => 'Forhindr downloads via mobildata';
	@override String get autoRemoveWatchedDownloads => 'Fjern sete downloads automatisk';
	@override String get autoRemoveWatchedDownloadsDescription => 'Slet sete downloads automatisk';
	@override String get cellularDownloadBlocked => 'Downloads er blokeret på mobilnettet. Brug Wi-Fi, eller skift indstillingen.';
	@override String get maxVolume => 'Maksimal lydstyrke';
	@override String get maxVolumeDescription => 'Tillad lydstyrkeforstærkning over 100 % for stille medier';
	@override String maxVolumePercent({required Object percent}) => '${percent}%';
	@override String get discordRichPresence => 'Discord Rich Presence';
	@override String get discordRichPresenceDescription => 'Vis på Discord, hvad du ser';
	@override String get services => 'Tjenester';
	@override String get servicesDescription => 'Forbind Trakt, MyAnimeList, Seerr og mere';
	@override String get manageLibrariesDescription => 'Omarranger og skjul biblioteker';
	@override String get companionRemoteServer => 'Fjernbetjeningsserver';
	@override String get companionRemoteServerDescription => 'Tillad mobilenheder på dit netværk at styre denne app';
	@override String get companionRemoteServerStartFailed => 'Fjernbetjeningsserveren kunne ikke startes';
	@override String get companionRemoteServerStopFailed => 'Fjernbetjeningsserveren kunne ikke stoppes';
	@override String get autoPip => 'Automatisk billede-i-billede';
	@override String get autoPipDescription => 'Skift automatisk til billede-i-billede, når du forlader appen under afspilning';
	@override String get matchContentFrameRate => 'Tilpas billedhastigheden til indholdet';
	@override String get matchContentFrameRateDescription => 'Tilpas skærmens opdateringsfrekvens til videoindhold';
	@override String get matchContentResolution => 'Tilpas til indholdets opløsning';
	@override String get matchContentResolutionDescription => 'Skifter skærmen til videoens oprindelige opløsning, så dit tv står for opskaleringen. Menuer og undertekster opskaleres også under afspilning';
	@override String get matchRefreshRate => 'Tilpas opdateringsfrekvensen';
	@override String get matchRefreshRateDescription => 'Tilpas skærmens opdateringsfrekvens i fuld skærm';
	@override String get matchDynamicRange => 'Tilpas dynamikområdet';
	@override String get matchDynamicRangeDescription => 'Slå HDR til for HDR-indhold og derefter tilbage til SDR';
	@override String get displaySwitchDelay => 'Forsinkelse ved skærmskift';
	@override String get tunneledPlayback => 'Tunneleret afspilning';
	@override String get tunneledPlaybackDescription => 'Brug videotunneling. Slå fra, hvis HDR-afspilning viser sort video, eller bevægelser hakker.';
	@override String get audioPassthrough => 'Lyd-passthrough';
	@override String get audioPassthroughDescription => 'Send Dolby/DTS-lyd til din receiver eller dit TV uden genkodning, så surroundlyd bevares. Slå fra, hvis du ikke har lyd.';
	@override String get audioPassthroughDescriptionAppleTv => 'Brug Apples indbyggede Dolby-dekoder til Dolby Digital Plus, inklusive Atmos. DTS og TrueHD afspilles stadig som flerkanals-PCM. Slå fra, hvis du ikke har lyd.';
	@override String get audioPassthroughOverriddenByNormalization => 'Fra, mens lydstyrkenormalisering er slået til';
	@override String get downmixCenterBoost => 'Forstærkning af centerkanal';
	@override String downmixCenterBoostValue({required Object db}) => '${db} dB';
	@override String get downmixCenterBoostLabel => 'Forstærkning (dB)';
	@override String get downmixCenterBoostShort => 'dB';
	@override String get audioDownmixNormalize => 'Normaliser lydstyrken ved downmix';
	@override String get audioDownmixNormalizeDescription => 'Sænk mixets lydstyrke for at undgå clipping. Slå fra for at bevare den oprindelige lydstyrke (høje scener kan blive forvrænget).';
	@override String get dvConversionMode => 'Dolby Vision-konvertering';
	@override String get dvConversionModeDescription => 'Vælg, hvordan Dolby Vision Profile 7-filer håndteres.';
	@override String get dvConversionAuto => 'Automatisk';
	@override String get dvConversionNative => 'Indbygget / deaktiveret';
	@override String get dvConversionDv81 => 'P7 → P8.1';
	@override String get dvConversionHevcStrip => 'P7 → HEVC';
	@override String get dvConversionAutoDescription => 'Brug registrering af enhedens funktioner og normal reserveadfærd';
	@override String get dvConversionNativeDescription => 'Gennemtving indbygget DV7-understøttelse, og undlad at forsøge DV-konvertering igen';
	@override String get dvConversionDv81Description => 'Tving inline RPU-konvertering til Dolby Vision profil 8.1';
	@override String get dvConversionHevcStripDescription => 'Fjern Dolby Vision RPU/EL-lag og brug almindelig HEVC';
	@override String get disableDolbyVision => 'Deaktiver Dolby Vision';
	@override String get disableDolbyVisionDescription => 'Afspil filens HDR10- eller HLG-lag i stedet for Dolby Vision, når det findes';
	@override String get hdrSdrConversion => 'HDR til SDR-konvertering';
	@override String get hdrSdrConversionDescription => 'Vælg, hvad der konverterer HDR-video, når skærmen ikke kan vise HDR.';
	@override String get hdrSdrConversionAuto => 'Automatisk';
	@override String get hdrSdrConversionAutoDescription => 'Enhed på Android 9 og nyere, afspiller på ældre versioner';
	@override String get hdrSdrConversionDevice => 'Enhed';
	@override String get hdrSdrConversionDeviceDescription => 'Enhedens videohardware konverterer. Hurtigst, men farverne afhænger af enheden';
	@override String get hdrSdrConversionPlayer => 'Afspiller';
	@override String get hdrSdrConversionPlayerDescription => 'Afspilleren konverterer. Ensartede farver, men 4K kan hakke på billige tv-bokse';
	@override String get deinterlace => 'Deinterlacing';
	@override String get deinterlaceDescription => 'Fjern kamartefakter fra interlaced video (kun mpv-afspiller)';
	@override String get requireProfileSelectionOnOpen => 'Spørg om profil ved åbning';
	@override String get requireProfileSelectionOnOpenDescription => 'Vis profilvalg hver gang appen åbnes';
	@override String get forceTvMode => 'Gennemtving TV-tilstand';
	@override String get forceTvModeDescription => 'Tving TV-layout. Til enheder, der ikke registreres automatisk. Kræver genstart.';
	@override String get startInFullscreen => 'Start i fuldskærm';
	@override String get startInFullscreenDescription => 'Åbn Plezy i fuldskærmstilstand ved opstart';
	@override String get exitFullscreenOnPlayerClose => 'Forlad fuldskærm ved lukning af afspiller';
	@override String get exitFullscreenOnPlayerCloseDescription => 'Afslut automatisk fuldskærm, når videoafspilleren lukkes';
	@override String get autoHidePerformanceOverlay => 'Skjul ydelsesoverlay automatisk';
	@override String get autoHidePerformanceOverlayDescription => 'Lad ydelsesoverlayet tone ud sammen med afspilningsknapperne';
	@override String get showNavBarLabels => 'Vis tekst på navigationslinjen';
	@override String get showNavBarLabelsDescription => 'Vis tekst under ikonerne på navigationslinjen';
	@override String get startupSection => 'Startsektion';
	@override String get showExploreTab => 'Vis fanen Opdag';
	@override String get general => 'Generelt';
	@override String get generalDescription => 'Sprog, opstart og vinduesadfærd';
	@override String get languageAndRegion => 'Sprog og region';
	@override String get startup => 'Opstart';
	@override String get display => 'Skærm';
	@override String get libraryAndCards => 'Bibliotek og kort';
	@override String get homeScreen => 'Startskærm';
	@override String get navigation => 'Navigation';
	@override String get window => 'Vindue';
	@override String get liveTv => 'Live TV';
	@override String get player => 'Afspiller';
	@override String get videoAndDisplay => 'Video og skærm';
	@override String get audio => 'Lyd';
	@override String get quality => 'Kvalitet';
	@override String get subtitles => 'Undertekster';
	@override String get seekAndTiming => 'Søgning og timing';
	@override String get behavior => 'Adfærd';
	@override String get gestures => 'Bevægelser';
	@override String get gestureBrightnessSwipe => 'Lysstyrke-strygning';
	@override String get gestureBrightnessSwipeDescription => 'Stryg op eller ned i venstre kant for at justere lysstyrken';
	@override String get gestureVolumeSwipe => 'Lydstyrke-strygning';
	@override String get gestureVolumeSwipeDescription => 'Stryg op eller ned i højre kant for at justere lydstyrken';
	@override String get gesturePinchToZoom => 'Klem for at zoome';
	@override String get gesturePinchToZoomDescription => 'Klem på videoen for at zoome ind eller ud';
	@override String get rememberBrightnessLevel => 'Husk lysstyrkeniveau';
	@override String get rememberBrightnessLevelDescription => 'Start afspilning med den lysstyrke, der blev indstillet med den seneste strygning';
	@override String get controls => 'Kontroller';
	@override String get rememberPlayerChanges => 'Husk afspillerændringer';
	@override String get rememberPlayerChangesDescription => 'Hvor en ændring under afspilning gemmes og anvendes igen';
	@override String get scopePlaybackSpeed => 'Afspilningshastighed';
	@override String get scopeShaderPreset => 'Shader-forudindstilling';
	@override String get scopeAspectRatio => 'Billedformat';
	@override String get scopeSyncOffsets => 'Synkronisering af lyd og undertekster';
	@override String get playerScopeOff => 'Gem ikke';
	@override String get playerScopeGlobal => 'Overalt';
	@override String get playerScopeLibrary => 'Pr. bibliotek';
	@override String get playerScopeTitle => 'Pr. serie eller film';
	@override String get exportDialogTitle => 'Eksportér Plezy-indstillinger';
}

// Path: search
class _Translations$search$da extends Translations$search$en {
	_Translations$search$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get hint => 'Søg film, serier, musik...';
	@override String get tryDifferentTerm => 'Prøv en anden søgning';
	@override String get searchYourMedia => 'Søg i dine medier';
	@override String get enterTitleActorOrKeyword => 'Indtast titel, skuespiller eller nøgleord';
}

// Path: hotkeys
class _Translations$hotkeys$da extends Translations$hotkeys$en {
	_Translations$hotkeys$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String setShortcutFor({required Object actionName}) => 'Indstil genvej for ${actionName}';
	@override String get clearShortcut => 'Ryd genvej';
	@override String get noShortcutSet => 'Ingen genvej angivet';
	@override String get currentShortcut => 'Nuværende genvej:';
	@override String get pressToRecord => 'Vælg for at registrere en genvej';
	@override String get recordingShortcut => 'Tryk på genvejen nu';
	@override late final _Translations$hotkeys$actions$da actions = _Translations$hotkeys$actions$da._(_root);
}

// Path: fileInfo
class _Translations$fileInfo$da extends Translations$fileInfo$en {
	_Translations$fileInfo$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Filinfo';
	@override String get overview => 'Oversigt';
	@override String get video => 'Video';
	@override String get audio => 'Lyd';
	@override String get subtitles => 'Undertekster';
	@override String get images => 'Indlejrede billeder';
	@override String get dataStreams => 'Datastrømme';
	@override String get lyrics => 'Tekster';
	@override String get file => 'Fil';
	@override String get attachments => 'Vedhæftninger';
	@override String get delivery => 'Levering';
	@override String versionCounter({required Object index, required Object count}) => 'Version ${index} af ${count}';
	@override String fileCounter({required Object index, required Object count}) => 'Fil ${index} af ${count}';
	@override String get noStreams => 'Serveren rapporterede ingen strømme for denne fil.';
	@override String get copyPath => 'Kopiér sti';
	@override String get pathCopied => 'Filstien er kopieret';
	@override String get codec => 'Codec';
	@override String get codecTag => 'Codec-tag';
	@override String get resolution => 'Opløsning';
	@override String get codedResolution => 'Kodet opløsning';
	@override String get bitrate => 'Bitrate';
	@override String get frameRate => 'Billedhastighed';
	@override String get rotation => 'Rotation';
	@override String get comment => 'Kommentar';
	@override String get audioDescription => 'Lydbeskrivelse';
	@override String get headerCompression => 'Headerkomprimering';
	@override String get sidecarFile => 'Sidecar-fil';
	@override String get transportTimestamp => 'Transporttidsstempel';
	@override String get displayOffset => 'Visningsforskydning';
	@override String get previewFailureCode => 'Preview-fejlkode';
	@override String get previewRetries => 'Preview-forsøg';
	@override String get aspectRatio => 'Billedformat';
	@override String get pixelAspectRatio => 'Pixel-billedformat';
	@override String get profile => 'Profil';
	@override String get level => 'Niveau';
	@override String get bitDepth => 'Bitdybde';
	@override String get pixelFormat => 'Pixelformat';
	@override String get colorSpace => 'Farverum';
	@override String get colorRange => 'Farveområde';
	@override String get colorPrimaries => 'Farveprimærer';
	@override String get colorTransfer => 'Farveoverførsel';
	@override String get chromaSubsampling => 'Chroma-subsampling';
	@override String get chromaLocation => 'Chroma-placering';
	@override String get scanType => 'Scanningstype';
	@override String get interlaced => 'Interlaced';
	@override String get anamorphic => 'Anamorfisk';
	@override String get referenceFrames => 'Referenceframes';
	@override String get dynamicRange => 'Dynamisk område';
	@override String get dolbyVision => 'Dolby Vision';
	@override String get dolbyVisionLevel => 'Dolby Vision-niveau';
	@override String get dolbyVisionVersion => 'Dolby Vision-version';
	@override String get dolbyVisionLayers => 'Dolby Vision-lag';
	@override String get baseLayerCompatibility => 'Basislagskompatibilitet';
	@override String get avcBitstream => 'AVC-bitstrøm';
	@override String get nalLengthSize => 'NAL-længdestørrelse';
	@override String get scalingMatrix => 'Brugerdefineret skaleringsmatrix';
	@override String get streamIdentifier => 'Strømidentifikator';
	@override String get streamIndex => 'Strømindex';
	@override String get streamId => 'Strøm-ID';
	@override String get language => 'Sprog';
	@override String get languageCode => 'Sprogkode';
	@override String get streamTitle => 'Sportitel';
	@override String get channels => 'Kanaler';
	@override String get sampleRate => 'Samplingshastighed';
	@override String get spatialAudio => 'Rumlig lyd';
	@override String get textBased => 'Tekstbaseret';
	@override String get subtitleFormat => 'Sidecar-format';
	@override String get provider => 'Udbydder';
	@override String get matchScore => 'Matchscore';
	@override String get externalDelivery => 'Kan leveres separat';
	@override String get sidecarPath => 'Sidecar-sti';
	@override String get sourceStream => 'Kopieret fra';
	@override String get temporary => 'Midlertidig';
	@override String get timeBase => 'Tidsbase';
	@override String get overallBitrate => 'Samlet bitrate';
	@override String get path => 'Sti';
	@override String get fileName => 'Filnavn';
	@override String get size => 'Størrelse';
	@override String get totalSize => 'Samlet størrelse';
	@override String get container => 'Container';
	@override String get duration => 'Varighed';
	@override String get previewThumbnails => 'Preview-thumbnails';
	@override String get previewIndex => 'Preview-index';
	@override String get packetLength => 'Pakkelængde';
	@override String get filePresent => 'Fil til stede';
	@override String get fileReadable => 'Læsbar af serveren';
	@override String get streamPath => 'Strømsti';
	@override String get optimizedForStreaming => 'Optimeret til streaming';
	@override String get has64bitOffsets => '64-bit-forskydninger';
	@override String get protocol => 'Protokol';
	@override String get mediaType => 'Medietype';
	@override String get sourceKind => 'Kildetype';
	@override String get optimizedVersion => 'Optimeret version';
	@override String get optimizationTarget => 'Optimeringsmål';
	@override String get deletedAt => 'Slettet';
	@override String get remoteSource => 'Fjernkilde';
	@override String get infiniteStream => 'Uendelig strøm';
	@override String get directPlay => 'Direkte afspilning';
	@override String get directStream => 'Direkte strømning';
	@override String get transcoding => 'Transkodning';
	@override String get etag => 'ETag';
	@override String get versionId => 'Versions-ID';
	@override String get fileId => 'Fil-ID';
	@override String get defaultAudioTrack => 'Standard lydspor';
	@override String get defaultSubtitleTrack => 'Standard undertekstspor';
	@override String get subtitlesOff => 'Fra';
	@override String get flagDefault => 'Standard';
	@override String get flagForced => 'Tvunget';
	@override String get flagSelected => 'Valgt';
	@override String get flagExternal => 'Ekstern';
	@override String get flagHearingImpaired => 'Hørehæmmede';
	@override String get flagDub => 'Dub';
	@override String get flagOriginal => 'Original';
	@override String get channelsMono => 'Mono';
	@override String dolbyVisionProfile({required Object profile}) => 'Profil ${profile}';
}

// Path: mediaMenu
class _Translations$mediaMenu$da extends Translations$mediaMenu$en {
	_Translations$mediaMenu$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get markAsWatched => 'Markér som set';
	@override String get markAsUnwatched => 'Markér som uset';
	@override String get removeFromContinueWatching => 'Fjern fra Fortsæt med at se';
	@override String get viewDetails => 'Vis detaljer';
	@override String get goToSeries => 'Gå til serie';
	@override String get shufflePlay => 'Afspil tilfældigt';
	@override String get shuffleNotAvailableOffline => 'Tilfældig afspilning er ikke tilgængelig offline';
	@override String get fileInfo => 'Filinfo';
	@override String get rate => 'Bedøm';
	@override String get playFromBeginning => 'Afspil fra begyndelsen';
	@override String get playVersion => 'Afspil version...';
}

// Path: rateSheet
class _Translations$rateSheet$da extends Translations$rateSheet$en {
	_Translations$rateSheet$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Bedøm';
	@override String get server => 'Server';
	@override String get favorite => 'Favorit';
	@override String get favorited => 'Føjet til favoritter';
	@override String get saved => 'Gemt';
	@override String get notAvailable => 'Intet match fundet';
	@override String get noConnectedServices => 'Forbind en tjeneste under Indstillinger for at bedømme via den.';
}

// Path: accessibility
class _Translations$accessibility$da extends Translations$accessibility$en {
	_Translations$accessibility$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String mediaCardMovie({required Object title}) => '${title}, film';
	@override String mediaCardShow({required Object title}) => '${title}, TV-serie';
	@override String mediaCardEpisode({required Object title, required Object episodeInfo}) => '${title}, ${episodeInfo}';
	@override String mediaCardSeason({required Object title, required Object seasonInfo}) => '${title}, ${seasonInfo}';
	@override String get mediaCardWatched => 'set';
	@override String mediaCardPartiallyWatched({required Object percent}) => '${percent} procent set';
	@override String get mediaCardUnwatched => 'uset';
	@override String get tapToPlay => 'Tryk for at afspille';
	@override String get decrease => 'Formindsk';
	@override String get increase => 'Forøg';
	@override String decreaseValue({required Object label}) => 'Formindsk ${label}';
	@override String increaseValue({required Object label}) => 'Forøg ${label}';
	@override String get hue => 'Farvetone';
	@override String get saturation => 'Mætning';
	@override String get brightness => 'Lysstyrke';
	@override String get hexColor => 'Hexfarve';
	@override String get expandText => 'Udvid tekst';
	@override String get collapseText => 'Fold tekst sammen';
	@override String get alphabetNavigation => 'Alfabetnavigation';
	@override String get alphabetScrollHint => 'Stryg op eller ned for at flytte ét bogstav';
	@override String rowColumnPosition({required Object row, required Object rowCount, required Object column, required Object columnCount}) => 'Række ${row} af ${rowCount}, kolonne ${column} af ${columnCount}';
	@override String rowPosition({required Object row, required Object rowCount}) => 'Række ${row} af ${rowCount}';
	@override String get autoScrollPlay => 'Start automatisk rulning';
	@override String get autoScrollPause => 'Sæt automatisk rulning på pause';
	@override String get hueShort => 'H';
	@override String get saturationShort => 'S';
	@override String get valueShort => 'V';
}

// Path: tooltips
class _Translations$tooltips$da extends Translations$tooltips$en {
	_Translations$tooltips$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get shufflePlay => 'Afspil tilfældigt';
	@override String get playTrailer => 'Afspil trailer';
	@override String get markAsWatched => 'Markér som set';
	@override String get markAsUnwatched => 'Markér som uset';
}

// Path: audioTracks
class _Translations$audioTracks$da extends Translations$audioTracks$en {
	_Translations$audioTracks$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String track({required Object n}) => 'Lydspor ${n}';
}

// Path: videoControls
class _Translations$videoControls$da extends Translations$videoControls$en {
	_Translations$videoControls$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get audioLabel => 'Lyd';
	@override String get subtitlesLabel => 'Undertekster';
	@override String addTime({required Object amount, required Object unit}) => '+${amount}${unit}';
	@override String get letterbox => 'Letterbox';
	@override String get fillScreen => 'Fyld skærm';
	@override String get stretch => 'Stræk';
	@override String get lockRotation => 'Lås rotation';
	@override String get unlockRotation => 'Lås rotation op';
	@override String get timerActive => 'Timer aktiv';
	@override String playbackWillPauseIn({required Object duration}) => 'Afspilningen sættes på pause om ${duration}';
	@override String get sleepTimerEndOfVideo => 'Slutningen af aktuel video';
	@override String get sleepTimerStopAtHeader => 'Stop ved';
	@override String get sleepTimerDurationHeader => 'Varighed';
	@override String get playbackWillPauseAtEnd => 'Afspilningen sættes på pause ved slutningen af denne video';
	@override String get stillWatching => 'Ser du stadig?';
	@override String pausingIn({required Object seconds}) => 'Sætter på pause om ${seconds} s';
	@override String get continueWatching => 'Fortsæt';
	@override String get autoPlayNext => 'Afspil næste automatisk';
	@override String get playNext => 'Afspil næste';
	@override String get playButton => 'Afspil';
	@override String get pauseButton => 'Pause';
	@override String get playbackPaused => 'Pauseret';
	@override String get playbackResumed => 'Afspiller';
	@override String get loadingVideo => 'Indlæser video';
	@override String get showPlaybackControls => 'Vis afspilningsknapper';
	@override String get hidePlaybackControls => 'Skjul afspilningsknapper';
	@override String seekBackwardButton({required Object seconds}) => 'Spol ${seconds} sekunder tilbage';
	@override String seekForwardButton({required Object seconds}) => 'Spol ${seconds} sekunder frem';
	@override String get previousButton => 'Forrige episode';
	@override String get nextButton => 'Næste episode';
	@override String get previousChapterButton => 'Forrige kapitel';
	@override String get nextChapterButton => 'Næste kapitel';
	@override String get muteButton => 'Slå lyden fra';
	@override String get unmuteButton => 'Slå lyden til';
	@override String get settingsButton => 'Afspilningsindstillinger';
	@override String get tracksButton => 'Lyd og undertekster';
	@override String get chaptersButton => 'Kapitler';
	@override String get versionQualityButton => 'Version og kvalitet';
	@override String get versionColumnHeader => 'Version';
	@override String get qualityColumnHeader => 'Kvalitet';
	@override String get qualityOriginal => 'Original';
	@override String qualityPresetLabel({required Object resolution, required Object bitrate}) => '${resolution}p ${bitrate} Mbps';
	@override String get transcodeUnavailableFallback => 'Transkodning utilgængelig — afspiller original kvalitet';
	@override String get subtitleUnavailableFallback => 'De valgte undertekster kunne ikke indlæses — afspilningen fortsætter uden undertekster';
	@override String get pipButton => 'Billede-i-billede-tilstand';
	@override String get aspectRatioButton => 'Billedformat';
	@override String get ambientLighting => 'Omgivelsesbelysning';
	@override String get fullscreenButton => 'Fuldskærm';
	@override String get exitFullscreenButton => 'Forlad fuldskærm';
	@override String get alwaysOnTopButton => 'Altid øverst';
	@override String get rotationLockButton => 'Rotationslås';
	@override String get lockScreen => 'Lås skærm';
	@override String get screenLockButton => 'Skærmlås';
	@override String get longPressToUnlock => 'Hold nede for at låse op';
	@override String get timelineSlider => 'Videotidslinje';
	@override String get volumeSlider => 'Lydstyrkeniveau';
	@override String endsAt({required Object time}) => 'Slutter kl. ${time}';
	@override String get pipActive => 'Afspiller i billede-i-billede';
	@override String get pipFailed => 'Billede-i-billede kunne ikke starte';
	@override String get screenshotSaved => 'Skærmbillede gemt';
	@override String zoomPercent({required Object percent}) => 'Zoom ${percent}%';
	@override String volumePercent({required Object percent}) => 'Lydstyrke ${percent}%';
	@override late final _Translations$videoControls$pipErrors$da pipErrors = _Translations$videoControls$pipErrors$da._(_root);
	@override String get chapters => 'Kapitler';
	@override String get noChaptersAvailable => 'Ingen kapitler tilgængelige';
	@override String get queue => 'Kø';
	@override String get noQueueItems => 'Ingen elementer i køen';
	@override String get noAudioDevicesAvailable => 'Ingen lydenheder tilgængelige';
	@override String get searchSubtitles => 'Søg undertekster';
	@override String get language => 'Sprog';
	@override String get noSubtitlesFound => 'Ingen undertekster fundet';
	@override String get subtitleDownloaded => 'Undertekst downloadet';
	@override String get subtitleDownloadedNotApplied => 'Underteksten blev downloadet, men kunne ikke vælges';
	@override String get subtitleDownloadFailed => 'Kunne ikke downloade undertekst';
	@override String get searchLanguages => 'Søg sprog...';
	@override String get skipIntro => 'Spring intro over';
	@override String get skipCredits => 'Spring rulletekster over';
	@override String get nextEpisode => 'Næste episode';
	@override String subtitleTrack({required Object n}) => 'Spor ${n}';
	@override String subtitleFile({required Object name}) => 'Undertekst ${name}';
	@override String forcedTrack({required Object label}) => '${label} (tvunget)';
	@override String get osdSubtitlesOff => 'Undertekster: Fra';
	@override String osdSubtitles({required Object track}) => 'Undertekster: ${track}';
	@override String osdAudio({required Object track}) => 'Lyd: ${track}';
}

// Path: messages
class _Translations$messages$da extends Translations$messages$en {
	_Translations$messages$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get markedAsWatched => 'Markeret som set';
	@override String get markedAsUnwatched => 'Markeret som uset';
	@override String get markedAsWatchedOffline => 'Markeret som set (synkroniseres online)';
	@override String get markedAsUnwatchedOffline => 'Markeret som uset (synkroniseres online)';
	@override String autoRemovedWatchedDownload({required Object title}) => 'Automatisk fjernet: ${title}';
	@override String autoRemovedWatchedDownloads({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n,
		one: 'Fjernede automatisk ${n} set download',
		other: 'Fjernede automatisk ${n} sete downloads',
	);
	@override String get removedFromContinueWatching => 'Fjernet fra Fortsæt med at se';
	@override String errorLoading({required Object error}) => 'Fejl: ${error}';
	@override String get searchPartialResults => 'Nogle medieservere kunne ikke søges i. Viser tilgængelige resultater.';
	@override String get streamInterrupted => 'Streamen blev afbrudt. Tryk på afspil, eller spol for at prøve igen.';
	@override String get fileInfoNotAvailable => 'Filinfo ikke tilgængelig';
	@override String get playbackAuthenticationRequired => 'Log ind på medieserveren igen for at afspille dette element.';
	@override String get playbackServerUnavailable => 'Medieserveren er ikke tilgængelig. Prøv igen senere.';
	@override String get playbackDataInvalid => 'Serveren returnerede ugyldige afspilningsoplysninger.';
	@override String get playbackCancelled => 'Afspilningen blev annulleret.';
	@override String get playbackFailed => 'Afspilningen kunne ikke startes.';
	@override String playbackFailedDetail({required Object error}) => 'Afspilningen kunne ikke startes: ${error}';
	@override String get audioOutputFailed => 'Lydoutputtet reagerer ikke længere. Tjek lydforbindelsen til tv\'et eller receiveren; hvis andre apps heller ikke har lyd, skal du genstarte enheden.';
	@override String get mediaUnavailable => 'Dette indhold er ikke længere tilgængeligt.';
	@override String errorLoadingFileInfo({required Object error}) => 'Fejl ved indlæsning af filinfo: ${error}';
	@override String get errorLoadingSeries => 'Fejl ved indlæsning af serie';
	@override String get musicNotSupported => 'Musikafspilning understøttes endnu ikke';
	@override String get noDescriptionAvailable => 'Ingen beskrivelse tilgængelig';
	@override String get noProfilesAvailable => 'Ingen profiler tilgængelige';
	@override String get contactAdminForProfiles => 'Kontakt din serveradministrator for at tilføje profiler';
	@override String get unableToDetermineLibrarySection => 'Kunne ikke finde bibliotekssektionen for dette element';
	@override String get logsCleared => 'Logfilerne blev ryddet';
	@override String get logsCopied => 'Logfilerne blev kopieret til udklipsholderen';
	@override String get noLogsAvailable => 'Ingen logfiler tilgængelige';
	@override String get logoutConfirm => 'Er du sikker på, at du vil logge ud?';
	@override String get noSeasonsFound => 'Ingen sæsoner fundet';
	@override String get seasonsLoadFailed => 'Kunne ikke indlæse sæsoner';
	@override String get noEpisodesFound => 'Ingen episoder fundet i første sæson';
	@override String get noEpisodesFoundGeneral => 'Ingen episoder fundet';
	@override String get episodesLoadFailed => 'Kunne ikke indlæse episoder';
	@override String get noResultsFound => 'Ingen resultater fundet';
	@override String sleepTimerSet({required Object label}) => 'Sove-timer indstillet til ${label}';
	@override String get noItemsAvailable => 'Ingen elementer tilgængelige';
	@override String get failedToCreatePlayQueueNoItems => 'Kunne ikke oprette en afspilningskø — ingen elementer';
	@override String failedPlayback({required Object action, required Object error}) => 'Kunne ikke ${action}: ${error}';
	@override String get switchingToCompatiblePlayer => 'Skifter til kompatibel afspiller...';
	@override String get serverLimitTitle => 'Afspilning mislykkedes';
	@override String get serverLimitBody => 'Serverfejl (HTTP 500). En båndbredde- eller transkodningsgrænse afviste sandsynligvis sessionen. Bed ejeren om at justere den.';
	@override String get mediaUnreadableTitle => 'Fil utilgængelig';
	@override String get mediaUnreadableBody => 'Serveren fandt dette emne, men kunne ikke læse filen (HTTP 404). Filen er sandsynligvis flyttet, slettet, eller dens lager er offline. Bed serverejeren om at kontrollere filen og scanne biblioteket igen.';
	@override String get serverBusyTitle => 'Stream er ikke tilgængelig';
	@override String get serverBusyBody => 'Serveren blev ved med at afvise at streame denne fil (HTTP 503). Den er muligvis ved at genstarte eller optaget, eller filens lager er muligvis offline. Prøv igen om et øjeblik – hvis det bliver ved med at ske, skal du bede serverejeren om at kontrollere serveren og filens lager.';
	@override String get playbackNotAllowedTitle => 'Afspilning er ikke tilladt';
	@override String get playbackNotAllowedBody => 'Serveren afviste at streame dette emne (HTTP 403). Din konto har muligvis ikke tilladelse til at afspille det, eller serveren tillader muligvis kun afspilning på sit lokale netværk.';
	@override String get logsUploaded => 'Logfilerne blev uploadet';
	@override String get logsUploadFailed => 'Logfilerne kunne ikke uploades';
	@override String get logId => 'Log-ID';
	@override String get burnedSubtitlesUseMenu => 'Underteksterne er indbrændt i denne stream. Skift dem i undertekstmenuen.';
	@override String get noVideoUrl => 'Ingen video-URL er tilgængelig';
	@override String get playbackDataNotPrepared => 'Afspilningen blev startet, før dens data var klar';
	@override String get trackSelectionNotRemembered => 'Dette sporvalg gælder kun for den aktuelle afspilning.';
	@override String get serverUnavailableForProfile => 'Ingen server er tilgængelig for den aktive profil';
}

// Path: subtitlingStyling
class _Translations$subtitlingStyling$da extends Translations$subtitlingStyling$en {
	_Translations$subtitlingStyling$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get text => 'Tekst';
	@override String get border => 'Kant';
	@override String get background => 'Baggrund';
	@override String get fontSize => 'Skriftstørrelse';
	@override String get textColor => 'Tekstfarve';
	@override String get borderSize => 'Kantstørrelse';
	@override String get borderColor => 'Kantfarve';
	@override String get backgroundOpacity => 'Baggrundsopacitet';
	@override String get backgroundColor => 'Baggrundsfarve';
	@override String get position => 'Position';
	@override String get assOverride => 'ASS-tilsidesættelse';
	@override String get overrideScale => 'Skaler';
	@override String get overrideForce => 'Gennemtving';
	@override String get overrideStrip => 'Fjern formatering';
	@override String get positionTop => 'Øverst';
	@override String get positionBottom => 'Nederst';
	@override String get useMargins => 'Brug margener';
	@override String get useMarginsDescription => 'Tillad tekstundertekster i området uden for videoen. Formaterede undertekster kan beholde deres oprindelige placering.';
	@override String get anchorToScreen => 'Fastgør til skærmen';
	@override String get anchorToScreenDescription => 'Vis tekstundertekster i de sorte bjælker under video i bredformat';
	@override String get bold => 'Fed';
	@override String get italic => 'Kursiv';
	@override String get renderResolution => 'Gengivelsesopløsning';
	@override String get renderResolutionScreen => 'Skærmopløsning';
	@override String get renderResolutionVideo => 'Videoopløsning';
}

// Path: mpvConfig
class _Translations$mpvConfig$da extends Translations$mpvConfig$en {
	_Translations$mpvConfig$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'mpv.conf';
	@override String get description => 'Avancerede videoafspillerindstillinger';
	@override String get presets => 'Forudindstillinger';
	@override String get noPresets => 'Ingen gemte forudindstillinger';
	@override String get saveAsPreset => 'Gem som forudindstilling...';
	@override String get presetName => 'Forudindstillingsnavn';
	@override String get presetNameHint => 'Indtast et navn for denne forudindstilling';
	@override String get loadPreset => 'Indlæs';
	@override String get deletePreset => 'Slet';
	@override String get presetSaved => 'Forudindstilling gemt';
	@override String get presetLoaded => 'Forudindstilling indlæst';
	@override String get presetDeleted => 'Forudindstilling slettet';
	@override String get confirmDeletePreset => 'Er du sikker på, at du vil slette denne forudindstilling?';
	@override String get configPlaceholder => 'gpu-api=vulkan\nhwdec=auto\n# comment';
	@override String get lineHint => 'option=value';
	@override String get addLine => 'Tilføj linje';
	@override String get removeLine => 'Fjern linje';
	@override String get embeddedVoHint => 'vo, gpu-context og gpu-api ignoreres på Linux: indlejret video renderes altid via vo=libmpv på videoplanen, og gpu-next (som compute-shaders som ArtCNN kræver) kan ikke køre indlejret.';
}

// Path: profiles
class _Translations$profiles$da extends Translations$profiles$en {
	_Translations$profiles$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get switchingProfile => 'Skifter profil…';
	@override String get active => 'Aktiv';
	@override String get manage => 'Administrer';
	@override String get delete => 'Slet';
	@override String get signOut => 'Log ud';
	@override String get signOutFailed => 'Kunne ikke logge ud.';
	@override String get sectionTitle => 'Profiler';
	@override String summaryMultipleWithActive({required Object count, required Object activeName}) => '${count} profiler · aktiv: ${activeName}';
	@override String summaryMultiple({required Object count}) => '${count} profiler';
	@override String get add => 'Tilføj';
	@override String get noConnections => 'Ingen forbindelser';
	@override String get incorrectPinTryAgain => 'Forkert PIN. Prøv igen.';
}

// Path: connections
class _Translations$connections$da extends Translations$connections$en {
	_Translations$connections$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Forbindelser';
	@override String get addConnection => 'Tilføj forbindelse';
	@override String sessionExpiredOne({required Object name}) => 'Sessionen er udløbet for ${name}';
	@override String sessionExpiredMany({required Object count}) => 'Sessionerne er udløbet for ${count} servere';
	@override String accessDeniedOne({required Object name}) => '${name} nægtede adgang for denne konto';
	@override String accessDeniedMany({required Object count}) => '${count} servere nægtede adgang for denne konto';
	@override String get signInAgain => 'Log ind igen';
}

// Path: accountPreferences
class _Translations$accountPreferences$da extends Translations$accountPreferences$en {
	_Translations$accountPreferences$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Kontopræferencer';
	@override String get unavailable => 'Kan ikke nå denne konto';
	@override String get autoSelectAudio => 'Vælg lyd ud fra sprog';
	@override String get subtitleMode => 'Slå undertekster til';
	@override late final _Translations$accountPreferences$subtitleModes$da subtitleModes = _Translations$accountPreferences$subtitleModes$da._(_root);
	@override late final _Translations$accountPreferences$forcedSubtitleOptions$da forcedSubtitleOptions = _Translations$accountPreferences$forcedSubtitleOptions$da._(_root);
	@override late final _Translations$accountPreferences$watchedIndicatorOptions$da watchedIndicatorOptions = _Translations$accountPreferences$watchedIndicatorOptions$da._(_root);
}

// Path: discover
class _Translations$discover$da extends Translations$discover$en {
	_Translations$discover$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Opdag';
	@override String get noContentAvailable => 'Intet indhold tilgængeligt';
	@override String get addMediaToLibraries => 'Tilføj medier til dine biblioteker';
	@override String get continueWatching => 'Fortsæt med at se';
	@override String get nextUp => 'Næste afsnit';
	@override String playEpisode({required Object season, required Object episode}) => 'S${season}E${episode}';
	@override String get overview => 'Oversigt';
	@override String get cast => 'Rollebesætning';
	@override String get extras => 'Trailere og ekstramateriale';
	@override String get studio => 'Studie';
	@override String get rating => 'Bedømmelse';
	@override String get director => 'Instruktør';
	@override String get directors => 'Instruktører';
	@override String get movie => 'Film';
	@override String get tvShow => 'TV-serie';
	@override String minutesLeft({required Object minutes}) => '${minutes} min tilbage';
	@override String get moreLikeThis => 'Mere som dette';
	@override String titleCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n,
		one: '${n} titel',
		other: '${n} titler',
	);
}

// Path: errors
class _Translations$errors$da extends Translations$errors$en {
	_Translations$errors$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String searchFailed({required Object error}) => 'Søgning mislykkedes: ${error}';
	@override String get searchUnavailable => 'Søgningen kunne ikke nå nogen medieserver.';
	@override String connectionTimeout({required Object context}) => 'Forbindelsen fik timeout under indlæsning af ${context}';
	@override String get connectionFailed => 'Kan ikke oprette forbindelse til medieserver';
	@override String unableToLoad({required Object context}) => 'Kunne ikke indlæse ${context}. Prøv igen.';
	@override String get noClientAvailable => 'Ingen klient tilgængelig';
	@override String failedToSwitchProfile({required Object displayName}) => 'Kunne ikke skifte til ${displayName}';
	@override String get failedToRate => 'Kunne ikke opdatere bedømmelsen';
	@override String get reasonTimedOut => 'forbindelsen fik timeout';
	@override String get reasonUnreachable => 'medieserveren kunne ikke nås';
	@override String get reasonRefused => 'medieserveren afviste anmodningen';
	@override String get reasonNotFound => 'elementet findes ikke længere på medieserveren';
	@override String get reasonServerError => 'medieserveren rapporterede en fejl';
	@override String get reasonCancelled => 'anmodningen blev annulleret';
	@override String get reasonUnexpected => 'der opstod en uventet fejl';
}

// Path: libraries
class _Translations$libraries$da extends Translations$libraries$en {
	_Translations$libraries$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Biblioteker';
	@override String get noLibrariesFound => 'Ingen biblioteker fundet';
	@override String get allLibrariesHidden => 'Alle biblioteker er skjult';
	@override String hiddenLibrariesCount({required Object count}) => 'Skjulte biblioteker (${count})';
	@override String get thisLibraryIsEmpty => 'Dette bibliotek er tomt';
	@override String get noItemsMatchFilters => 'Ingen elementer matcher de aktive filtre';
	@override String get resetFilters => 'Nulstil filtre';
	@override String get all => 'Alle';
	@override String get clearAll => 'Ryd alle';
	@override String get manageLibraries => 'Administrer biblioteker';
	@override String get sort => 'Sortér';
	@override String get sortBy => 'Sortér efter';
	@override String get filters => 'Filtre';
	@override String get showLibrary => 'Vis bibliotek';
	@override String get hideLibrary => 'Skjul bibliotek';
	@override String get libraryOptions => 'Biblioteksindstillinger';
	@override String get content => 'biblioteksindhold';
	@override String get selectLibrary => 'Vælg bibliotek';
	@override String filtersWithCount({required Object count}) => 'Filtre (${count})';
	@override String get noRecommendations => 'Ingen anbefalinger tilgængelige';
	@override String get noCollections => 'Ingen samlinger i dette bibliotek';
	@override String get noFoldersFound => 'Ingen mapper fundet';
	@override String get folders => 'mapper';
	@override late final _Translations$libraries$tabs$da tabs = _Translations$libraries$tabs$da._(_root);
	@override late final _Translations$libraries$groupings$da groupings = _Translations$libraries$groupings$da._(_root);
	@override late final _Translations$libraries$filterCategories$da filterCategories = _Translations$libraries$filterCategories$da._(_root);
	@override late final _Translations$libraries$sortLabels$da sortLabels = _Translations$libraries$sortLabels$da._(_root);
}

// Path: about
class _Translations$about$da extends Translations$about$en {
	_Translations$about$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Om';
	@override String get openSourceLicenses => 'Open source-licenser';
	@override String versionLabel({required Object version}) => 'Version ${version}';
	@override String get viewLicensesDescription => 'Se licenser for tredjepartsbiblioteker';
}

// Path: hubDetail
class _Translations$hubDetail$da extends Translations$hubDetail$en {
	_Translations$hubDetail$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Titel';
	@override String get releaseYear => 'Udgivelsesår';
	@override String get dateAdded => 'Tilføjelsesdato';
	@override String get rating => 'Bedømmelse';
	@override String get noItemsFound => 'Ingen elementer fundet';
}

// Path: logs
class _Translations$logs$da extends Translations$logs$en {
	_Translations$logs$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get clearLogs => 'Ryd logfiler';
	@override String get copyLogs => 'Kopiér logfiler';
	@override String get uploadLogs => 'Upload logfiler';
}

// Path: startup
class _Translations$startup$da extends Translations$startup$en {
	_Translations$startup$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get failedTitle => 'Plezy kunne ikke starte';
	@override String get failedBody => 'Der gik noget galt under opstart. Oplysningerne nedenfor viser, hvad der gik galt.';
	@override String get failedBodyRepairable => 'Plezy\'s gemte indstillingsfil er beskadiget og skal genopbygges, før Plezy kan starte. Det hjælper ikke at prøve igen — vælg Reparer lager.';
	@override String get phaseLabel => 'Trin';
	@override String get showDetails => 'Vis detaljer';
	@override String get hideDetails => 'Skjul detaljer';
	@override String get copyDetails => 'Kopiér detaljer';
	@override String get detailsCopied => 'Detaljer kopieret til udklipsholder';
	@override String get uploadDetails => 'Upload detaljer';
	@override String get repairStorage => 'Reparer lager';
	@override String get repairTitle => 'Reparer gemte data?';
	@override String get repairBodyCommon => 'Plezy\'s indstillingsfil er beskadiget og kan ikke læses. Reparation nulstiller alle indstillinger til deres standardværdier.';
	@override String get repairBodyOneCredential => 'Én gemt loginoplysning er beskadiget og kan ikke læses. Reparation fjerner kun den; dine andre indstillinger forbliver urørt.';
	@override String get repairBodySignInsKept => 'Dine servere og profiler bør forblive logget ind.';
	@override String get repairBodySignInsLost => 'Nøglen, der beskytter dine gemte loginoplysninger, kan ikke gendannes fra denne fil, så du skal logge ind på alle servere og profiler igen. Intet på din medieserver er påvirket.';
	@override String get repairBodySessionsUncertain => 'Trackere (MAL, AniList, Simkl, Trakt) og Seerr gemmes separat, og det er uvist, om de overlever. Plezy fortæller dig præcis, hvad det beholdt.';
	@override String get repairConfirm => 'Reparer';
	@override String get repairSucceeded => 'Lager repareret';
	@override String get repairNeedsRestart => 'Lager repareret — genstart påkrævet';
	@override String get restartRequiredBody => 'Dine data er blevet repareret, men Plezy skal starte på ny, før det kan bruge dem. Luk Plezy, og åbn det igen.';
	@override String get quitPlezy => 'Afslut Plezy';
	@override String get repairFailed => 'Reparation mislykkedes';
	@override String get repairKeptSignIns => 'Dine servere og profiler er stadig logget ind.';
	@override String get repairLostSignIns => 'Nøglen, der beskytter dine gemte loginoplysninger, kunne ikke gendannes. Du skal logge ind på alle servere og profiler igen.';
	@override String get repairLostSessions => 'Mindst én tracker- eller Seerr-forbindelse gik tabt og skal genetableres.';
	@override String get backupTitle => 'En kopi af den beskadigede fil blev gemt';
	@override String get backupWarning => 'Den indeholder dine loginoplysninger. Upload eller del den ikke.';
	@override String get deleteBackup => 'Slet kopi';
	@override String get backupDeleted => 'Kopi slettet.';
	@override String get previousFailureTitle => 'Plezy kunne ikke starte sidste gang';
}

// Path: licenses
class _Translations$licenses$da extends Translations$licenses$en {
	_Translations$licenses$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get relatedPackages => 'Relaterede pakker';
	@override String get license => 'Licens';
	@override String licenseNumber({required Object number}) => 'Licens ${number}';
	@override String licensesCount({required Object count}) => '${count} licenser';
}

// Path: navigation
class _Translations$navigation$da extends Translations$navigation$en {
	_Translations$navigation$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get libraries => 'Biblioteker';
	@override String get downloads => 'Downloads';
	@override String get liveTv => 'Live TV';
	@override String get explore => 'Udforsk';
}

// Path: explore
class _Translations$explore$da extends Translations$explore$en {
	_Translations$explore$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Udforsk';
	@override String get selectSource => 'Vælg kilde';
	@override late final _Translations$explore$rows$da rows = _Translations$explore$rows$da._(_root);
	@override late final _Translations$explore$status$da status = _Translations$explore$status$da._(_root);
	@override String episodeCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n,
		one: '${n} afsnit',
		other: '${n} afsnit',
	);
	@override String get cast => 'Rollebesætning';
	@override String get characters => 'Figurer';
	@override String get addToWatchlist => 'Føj til ønskeliste';
	@override String get removeFromWatchlist => 'Fjern fra ønskeliste';
	@override String get addedToWatchlist => 'Føjet til overvågningslisten';
	@override String get removedFromWatchlist => 'Fjernet fra overvågningslisten';
	@override String get watchlistUpdateFailed => 'Kunne ikke opdatere ønskelisten';
	@override String get watchlistNoMatch => 'Kunne ikke knytte dette element til en overvågningsliste';
	@override String get notInLibrary => 'Ikke i dit bibliotek';
	@override String get inTheseLibraries => 'I disse biblioteker';
	@override String get checkingLibrary => 'Tjekker dit bibliotek...';
	@override String libraryCheckFailed({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n,
		one: 'Kunne ikke tjekke ${n} server',
		other: 'Kunne ikke tjekke ${n} servere',
	);
	@override String get emptyTitle => 'Der er ikke noget her endnu';
	@override String emptyMessage({required Object source}) => 'Indholdsrækker fra ${source} vises her, når de har indhold.';
	@override String searchHint({required Object source}) => 'Søg i ${source}';
	@override String searchEmpty({required Object query}) => 'Ingen resultater for "${query}"';
	@override String searchPrompt({required Object source}) => 'Søg efter film og serier på ${source}.';
	@override String get searchFailed => 'Søgningen mislykkedes. Tjek din forbindelse, og prøv igen.';
	@override late final _Translations$explore$badge$da badge = _Translations$explore$badge$da._(_root);
	@override late final _Translations$explore$stats$da stats = _Translations$explore$stats$da._(_root);
	@override late final _Translations$explore$season$da season = _Translations$explore$season$da._(_root);
	@override late final _Translations$explore$format$da format = _Translations$explore$format$da._(_root);
	@override late final _Translations$explore$sourceMaterial$da sourceMaterial = _Translations$explore$sourceMaterial$da._(_root);
	@override late final _Translations$explore$creditRole$da creditRole = _Translations$explore$creditRole$da._(_root);
	@override late final _Translations$explore$relation$da relation = _Translations$explore$relation$da._(_root);
	@override String broadcast({required Object day, required Object time}) => 'Sendes ${day} kl. ${time}';
	@override String broadcastWithZone({required Object day, required Object time, required Object timezone}) => 'Sendes ${day} kl. ${time} ${timezone}';
	@override late final _Translations$explore$detail$da detail = _Translations$explore$detail$da._(_root);
	@override String totalResults({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n,
		one: '${n} resultat',
		other: '${n} resultater',
	);
}

// Path: liveTv
class _Translations$liveTv$da extends Translations$liveTv$en {
	_Translations$liveTv$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Live TV';
	@override String get serverUnavailable => 'Live-tv-serveren er ikke tilgængelig.';
	@override String get live => 'LIVE';
	@override String get searchHint => 'Søg efter kanaler og programmer';
	@override String get now => 'Nu';
	@override String get today => 'I dag';
	@override String get tomorrow => 'I morgen';
	@override String get joinSession => 'Deltag i igangværende session';
	@override String get record => 'Optag';
	@override String invalidPlaybackData({required Object product}) => '${product} returnerede ugyldige afspilningsdata for Live TV';
}

// Path: collections
class _Translations$collections$da extends Translations$collections$en {
	_Translations$collections$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Samlinger';
	@override String get collection => 'Samling';
	@override String get empty => 'Samlingen er tom';
	@override String get deleteCollection => 'Slet samling';
	@override String deleteConfirm({required Object title}) => 'Slet "${title}"? Dette kan ikke fortrydes.';
	@override String get deleted => 'Samling slettet';
	@override String get deleteFailed => 'Kunne ikke slette samling';
	@override String deleteFailedWithError({required Object error}) => 'Kunne ikke slette samling: ${error}';
	@override String get selectCollection => 'Vælg samling';
	@override String get collectionName => 'Samlingsnavn';
	@override String get enterCollectionName => 'Indtast samlingsnavn';
	@override String get addedToCollection => 'Tilføjet til samling';
	@override String get errorAddingToCollection => 'Kunne ikke tilføje til samling';
	@override String get created => 'Samling oprettet';
	@override String get removeFromCollection => 'Fjern fra samling';
	@override String removeFromCollectionConfirm({required Object title}) => 'Fjern "${title}" fra denne samling?';
	@override String get removedFromCollection => 'Fjernet fra samling';
	@override String get removeFromCollectionFailed => 'Kunne ikke fjerne fra samling';
	@override String removeFromCollectionError({required Object error}) => 'Fejl ved fjernelse fra samling: ${error}';
	@override String get searchCollections => 'Søg i samlinger...';
}

// Path: playlists
class _Translations$playlists$da extends Translations$playlists$en {
	_Translations$playlists$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Playlister';
	@override String get playlist => 'Playliste';
	@override String get noPlaylists => 'Ingen playlister fundet';
	@override String get create => 'Opret playliste';
	@override String get playlistName => 'Playlistenavn';
	@override String get enterPlaylistName => 'Indtast playlistenavn';
	@override String get delete => 'Slet playliste';
	@override String get removeItem => 'Fjern fra playliste';
	@override String get smartPlaylist => 'Smart playliste';
	@override String itemCount({required Object count}) => '${count} elementer';
	@override String get oneItem => '1 element';
	@override String get emptyPlaylist => 'Denne playliste er tom';
	@override String get deleteConfirm => 'Slet playliste?';
	@override String deleteMessage({required Object name}) => 'Er du sikker på, at du vil slette "${name}"?';
	@override String get created => 'Playliste oprettet';
	@override String get deleted => 'Playliste slettet';
	@override String get itemAdded => 'Tilføjet til playliste';
	@override String get itemRemoved => 'Fjernet fra playliste';
	@override String get selectPlaylist => 'Vælg playliste';
	@override String get searchPlaylists => 'Søg i playlister...';
	@override String get errorCreating => 'Kunne ikke oprette playliste';
	@override String get errorDeleting => 'Kunne ikke slette playliste';
	@override String get errorLoading => 'Kunne ikke indlæse playlister';
	@override String get errorAdding => 'Kunne ikke tilføje til playliste';
	@override String get errorReordering => 'Kunne ikke ændre rækkefølge på playlisteelement';
	@override String get errorRemoving => 'Kunne ikke fjerne fra playliste';
}

// Path: music
class _Translations$music$da extends Translations$music$en {
	_Translations$music$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get goToAlbum => 'Gå til album';
	@override String get goToArtist => 'Gå til kunstner';
	@override String get instantMix => 'Direkte miks';
	@override String get playNext => 'Afspil næste';
	@override String get addToQueue => 'Føj til kø';
	@override String discNumber({required Object n}) => 'Disk ${n}';
	@override String trackCount({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n,
		one: '${n} nummer',
		other: '${n} numre',
	);
	@override String get nowPlaying => 'Afspiller nu';
	@override String playingFrom({required Object title}) => 'Afspiller fra ${title}';
	@override String get queue => 'Kø';
	@override String get clearQueue => 'Ryd kø';
	@override String get lyrics => 'Sangtekst';
	@override String get noLyrics => 'Ingen sangtekst tilgængelig';
	@override String get sleepTimer => 'Sovetimer';
	@override String get sleepTimerEndOfTrack => 'Slutningen af nummeret';
	@override String sleepTimerMinutes({required Object n}) => '${n} minutter';
	@override String get stopPlayback => 'Stop afspilning';
	@override String get previousTrack => 'Forrige nummer';
	@override String get nextTrack => 'Næste nummer';
	@override String get repeat => 'Gentag';
	@override String get repeatAll => 'Gentag alle';
	@override String get repeatOne => 'Gentag ét nummer';
	@override String get instantMixNoServer => 'Ingen server er tilgængelig til et øjeblikkeligt mix';
	@override String get instantMixFailed => 'Kunne ikke indlæse det direkte miks';
	@override String get instantMixEmpty => 'Det direkte miks indeholdt ingen numre';
	@override String noAudioUrl({required Object track}) => 'Ingen lyd-URL er tilgængelig for ${track}';
	@override late final _Translations$music$discography$da discography = _Translations$music$discography$da._(_root);
}

// Path: watchTogether
class _Translations$watchTogether$da extends Translations$watchTogether$en {
	_Translations$watchTogether$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Se sammen';
	@override String get description => 'Se indhold synkroniseret med venner og familie';
	@override String get createSession => 'Opret session';
	@override String get creating => 'Opretter...';
	@override String get joinSession => 'Deltag i session';
	@override String get joining => 'Deltager...';
	@override String get controlMode => 'Kontroltilstand';
	@override String get controlModeQuestion => 'Hvem kan styre afspilning?';
	@override String get hostOnly => 'Kun vært';
	@override String get anyone => 'Alle';
	@override String get hostingSession => 'Er vært for sessionen';
	@override String get inSession => 'Deltager i en session';
	@override String get sessionCode => 'Sessionskode';
	@override String get openSessionControls => 'Åbn sessionsstyring for Se sammen';
	@override String get copySessionCode => 'Kopiér sessionskode';
	@override String get hostControlsPlayback => 'Værten styrer afspilningen';
	@override String get anyoneCanControl => 'Alle kan styre afspilningen';
	@override String get hostControls => 'Værten styrer';
	@override String get anyoneControls => 'Alle styrer';
	@override String get participants => 'Deltagere';
	@override String get host => 'Vært';
	@override String get hostBadge => 'VÆRT';
	@override String get youAreHost => 'Du er vært';
	@override String get makeHost => 'Gør til vært';
	@override String get makeHostQuestion => 'Overfør vært?';
	@override String makeHostConfirm({required Object name}) => '${name} styrer afspilningen og sessionen for alle.';
	@override String get transfer => 'Overfør';
	@override String hostChangedTo({required Object name}) => '${name} er nu vært';
	@override String get youAreNowHost => 'Du er nu værten';
	@override String hostTransferFailed({required Object name}) => 'Kunne ikke gøre ${name} til vært';
	@override String get watchingWithOthers => 'Ser med andre';
	@override String get endSession => 'Afslut session';
	@override String get leaveSession => 'Forlad session';
	@override String get endSessionQuestion => 'Afslut session?';
	@override String get leaveSessionQuestion => 'Forlad session?';
	@override String get endSessionConfirm => 'Dette afslutter sessionen for alle deltagere.';
	@override String get leaveSessionConfirm => 'Du vil blive fjernet fra sessionen.';
	@override String get endSessionConfirmOverlay => 'Dette afslutter fællesafspilningen for alle deltagere.';
	@override String get leaveSessionConfirmOverlay => 'Din forbindelse til fællesafspilningen afbrydes.';
	@override String get end => 'Afslut';
	@override String get leave => 'Forlad';
	@override String get syncing => 'Synkroniserer...';
	@override String get joinWatchSession => 'Deltag i fællesafspilning';
	@override String get enterCodeHint => 'Indtast 5-tegns kode';
	@override String get pasteFromClipboard => 'Indsæt fra udklipsholder';
	@override String get pleaseEnterCode => 'Indtast en sessionskode';
	@override String get codeMustBe5Chars => 'Sessionskode skal være 5 tegn';
	@override String get joinInstructions => 'Indtast værtens sessionskode for at deltage.';
	@override String get failedToCreate => 'Kunne ikke oprette session';
	@override String get failedToJoin => 'Kunne ikke deltage i session';
	@override String get sessionCodeCopied => 'Sessionskode kopieret til udklipsholder';
	@override String get relayUnreachable => 'Relayserveren kan ikke nås. Blokering hos internetudbyderen kan forhindre Se sammen.';
	@override String get reconnectingToHost => 'Genopretter forbindelse til vært...';
	@override String get currentPlayback => 'Nuværende afspilning';
	@override String get joinCurrentPlayback => 'Deltag i nuværende afspilning';
	@override String get joinCurrentPlaybackDescription => 'Hop tilbage til det værten ser nu';
	@override String get failedToOpenCurrentPlayback => 'Kunne ikke åbne nuværende afspilning';
	@override String participantJoined({required Object name}) => '${name} deltog';
	@override String participantLeft({required Object name}) => '${name} forlod';
	@override String participantPaused({required Object name}) => '${name} satte på pause';
	@override String participantResumed({required Object name}) => '${name} genoptog';
	@override String participantSeeked({required Object name}) => '${name} ændrede afspilningspositionen';
	@override String participantChangedSpeed({required Object name, required Object speed}) => '${name} satte hastigheden til ${speed}';
	@override String participantBuffering({required Object name}) => '${name} bufferer';
	@override String participantNeedsUpdate({required Object name}) => '${name} bruger en ældre appversion — synkronisering er ikke tilgængelig';
	@override String resumingWithout({required Object name}) => 'Fortsætter uden ${name}';
	@override String get waitingForParticipants => 'Venter på, at de andre bliver klar...';
	@override String waitingForName({required Object name}) => 'Venter på ${name}...';
	@override String get recentRooms => 'Seneste rum';
	@override String get renameRoom => 'Omdøb rum';
	@override String get removeRoom => 'Fjern';
	@override String get guestSwitchUnavailable => 'Kunne ikke skifte — server ikke tilgængelig for synkronisering';
	@override String get guestSwitchFailed => 'Kunne ikke skifte — indhold blev ikke fundet på denne server';
	@override String get defaultDisplayName => 'Bruger';
	@override late final _Translations$watchTogether$errors$da errors = _Translations$watchTogether$errors$da._(_root);
}

// Path: downloads
class _Translations$downloads$da extends Translations$downloads$en {
	_Translations$downloads$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Downloads';
	@override String get manage => 'Administrer';
	@override String get tvShows => 'TV-serier';
	@override String get movies => 'Film';
	@override String get music => 'Musik';
	@override String tracksQueued({required Object count}) => '${count} numre i kø til download';
	@override String get noDownloads => 'Ingen downloads endnu';
	@override String get noDownloadsDescription => 'Downloadet indhold vises her til offlinevisning';
	@override String get downloadNow => 'Download';
	@override String get deleteDownload => 'Slet download';
	@override String get retryDownload => 'Prøv download igen';
	@override String get downloadQueued => 'Download i kø';
	@override String get downloadResumed => 'Download genoptaget';
	@override String get serverErrorBitrate => 'Serverfejl: filen overskrider muligvis grænsen for ekstern bitrate';
	@override String get storageFull => 'Downloads blev stoppet for at beskytte den ledige lagerplads. Frigør plads, eller vælg en anden downloadplacering, og prøv igen.';
	@override String get storageUnavailable => 'Downloads blev stoppet, fordi den tilgængelige lagerplads ikke kunne kontrolleres. Tjek downloadplaceringen, og prøv igen.';
	@override String episodesQueued({required Object count}) => '${count} episoder i downloadkø';
	@override String get downloadDeleted => 'Download slettet';
	@override String deleteConfirm({required Object title}) => 'Slet "${title}" fra denne enhed?';
	@override String get cancelledDownloadTitle => 'Annulleret download';
	@override String get cancelledDownloadMessage => 'Denne download blev annulleret. Hvad vil du gøre?';
	@override String get allEpisodesAlreadyDownloaded => 'Alle episoder er allerede downloadet';
	@override String get resumeDownload => 'Genoptag download';
	@override String get cancelledDownload => 'Annulleret download';
	@override String syncingFile({required Object file, required Object status}) => '${file} (synkroniserer ${status})';
	@override String downloadedFileClickToComplete({required Object file}) => '${file} downloadet — klik for at fuldføre';
	@override String get partialDownloadClickToComplete => 'Delvist downloadet — klik for at fuldføre';
	@override String get deleting => 'Sletter...';
	@override String deletingWithProgress({required Object title, required Object current, required Object total}) => 'Sletter ${title}... (${current} af ${total})';
	@override String get queuedTooltip => 'I kø';
	@override String queuedFilesTooltip({required Object files}) => 'I kø: ${files}';
	@override String get downloadingTooltip => 'Downloader...';
	@override String downloadingFilesTooltip({required Object files}) => 'Downloader ${files}';
	@override String get noDownloadsTree => 'Ingen downloads';
	@override String get pauseAll => 'Sæt alle på pause';
	@override String get resumeAll => 'Genoptag alle';
	@override String get deleteAll => 'Slet alle';
	@override String get selectVersion => 'Vælg version';
	@override String get allEpisodes => 'Alle episoder';
	@override String get unwatchedOnly => 'Kun usete';
	@override String nextNUnwatched({required Object count}) => 'Næste ${count} usete';
	@override String get customAmount => 'Angiv antal...';
	@override String get includeSpecials => 'Medtag specialafsnit';
	@override String get howManyEpisodes => 'Hvor mange episoder?';
	@override String get invalidEpisodeCount => 'Indtast et gyldigt antal episoder.';
	@override String get keepSynced => 'Synkroniser løbende';
	@override String get downloadOnce => 'Download én gang';
	@override String keepNUnwatched({required Object count}) => 'Behold ${count} usete';
	@override String get editSyncRule => 'Rediger synkroniseringsregel';
	@override String get removeSyncRule => 'Fjern synkroniseringsregel';
	@override String removeSyncRuleConfirm({required Object title}) => 'Stop synkronisering af "${title}"? Downloadede episoder beholdes.';
	@override String removeListSyncRuleConfirm({required Object title}) => 'Stop synkronisering af "${title}"?';
	@override String get deleteSyncRuleDownloads => 'Slet også tilknyttede downloads';
	@override String get deleteSyncRuleDownloadsDescription => 'Downloads, der bruges af en anden synkroniseringsregel eller profil, beholdes.';
	@override String syncRuleCreated({required Object count}) => 'Synkroniseringsregel oprettet — beholder ${count} usete episoder';
	@override String get syncRuleUpdated => 'Synkroniseringsregel opdateret';
	@override String get syncRuleRemoved => 'Synkroniseringsregel fjernet';
	@override String get syncRuleAndDownloadsRemoved => 'Synkroniseringsregel og tilknyttede downloads fjernet';
	@override String get syncRuleCleanupBusy => 'Synkroniseringsregler opdateres lige nu. Prøv igen om et øjeblik.';
	@override String get syncRuleCleanupUnavailable => 'Tilknyttede downloads kunne ikke identificeres sikkert. Genopret forbindelse til serveren og prøv igen, eller fjern reglen uden at slette downloads.';
	@override String syncedNewEpisodes({required Object count, required Object title}) => 'Synkroniserede ${count} nye episoder for ${title}';
	@override String get activeSyncRules => 'Synkroniseringsregler';
	@override String get noSyncRules => 'Ingen synkroniseringsregler';
	@override String get manageSyncRule => 'Administrer synkronisering';
	@override String get editEpisodeCount => 'Antal episoder';
	@override String get editSyncFilter => 'Synkroniseringsfilter';
	@override String get syncAllItems => 'Synkroniserer alle elementer';
	@override String get syncUnwatchedItems => 'Synkroniserer usete elementer';
	@override String syncRuleServerContext({required Object server, required Object status}) => 'Server: ${server} • ${status}';
	@override String get syncRuleAvailable => 'Tilgængelig';
	@override String get syncRuleOffline => 'Offline';
	@override String get syncRuleSignInRequired => 'Login påkrævet';
	@override String get syncRuleAccessDenied => 'Adgang nægtet';
	@override String get syncRuleNotAvailableForProfile => 'Ikke tilgængelig for nuværende profil';
	@override String get syncRuleUnknownServer => 'Ukendt server';
	@override String get syncRuleListCreated => 'Synkroniseringsregel oprettet';
	@override late final _Translations$downloads$backgroundWarning$da backgroundWarning = _Translations$downloads$backgroundWarning$da._(_root);
	@override String get options => 'Valgmuligheder for downloads';
	@override late final _Translations$downloads$groupings$da groupings = _Translations$downloads$groupings$da._(_root);
	@override String get unknownLibrary => 'Ukendt bibliotek';
	@override String get unknownShow => 'Ukendt serie';
	@override String get unknownSeason => 'Ukendt sæson';
	@override String get unknownAlbum => 'Ukendt album';
	@override String completedOfTotal({required Object completed, required Object total}) => '${completed}/${total} fuldført';
	@override String get errorFileNotFound => 'Filen blev ikke fundet (404)';
	@override String get errorDownloadNotAllowed => 'Serveren tillader ikke download (403)';
	@override String get errorDownloadFailed => 'Download mislykkedes';
	@override String errorDownloadFailedWithReason({required Object reason}) => 'Download mislykkedes: ${reason}';
	@override String errorHttpStatus({required Object status}) => 'Download mislykkedes (HTTP ${status})';
	@override String errorPostProcessing({required Object reason}) => 'Efterbehandling mislykkedes: ${reason}';
	@override String get reasonFileNotSaved => 'filen kunne ikke gemmes på denne enhed';
	@override String get reasonCannotResume => 'den delvise download kunne ikke genoptages';
	@override String get reasonDeviceStorageFull => 'der er ikke mere lagerplads på denne enhed';
	@override String get notificationDownloading => 'Downloader...';
	@override String get notificationComplete => 'Download fuldført';
	@override String get notificationPaused => 'Download sat på pause';
}

// Path: shaders
class _Translations$shaders$da extends Translations$shaders$en {
	_Translations$shaders$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Shadere';
	@override String get noShaderDescription => 'Ingen videoforbedring';
	@override String get nvscalerDescription => 'NVIDIA-billedskalering for skarpere video';
	@override String get artcnnVariantNeutral => 'Neutral';
	@override String get artcnnVariantDenoise => 'Støjreduktion';
	@override String get artcnnVariantDenoiseSharpen => 'Støjreduktion + skarphed';
	@override String get qualityFast => 'Hurtig';
	@override String get qualityHQ => 'Høj kvalitet';
	@override String get mode => 'Tilstand';
	@override String get importShader => 'Importér shader';
	@override String get customShaderDescription => 'Brugerdefineret GLSL-shader';
	@override String get shaderImported => 'Shader importeret';
	@override String get shaderImportFailed => 'Kunne ikke importere shader';
	@override String get deleteShader => 'Slet shader';
	@override String deleteShaderConfirm({required Object name}) => 'Slet "${name}"?';
}

// Path: companionRemote
class _Translations$companionRemote$da extends Translations$companionRemote$en {
	_Translations$companionRemote$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Fjernbetjening';
	@override String connectedTo({required Object name}) => 'Forbundet til ${name}';
	@override String get unknownDevice => 'Ukendt enhed';
	@override late final _Translations$companionRemote$session$da session = _Translations$companionRemote$session$da._(_root);
	@override late final _Translations$companionRemote$pairing$da pairing = _Translations$companionRemote$pairing$da._(_root);
	@override late final _Translations$companionRemote$remote$da remote = _Translations$companionRemote$remote$da._(_root);
	@override late final _Translations$companionRemote$errors$da errors = _Translations$companionRemote$errors$da._(_root);
	@override String get closedBeforeAuth => 'Forbindelsen blev lukket før godkendelsen';
}

// Path: videoSettings
class _Translations$videoSettings$da extends Translations$videoSettings$en {
	_Translations$videoSettings$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get playbackSpeed => 'Afspilningshastighed';
	@override String get normalSpeed => 'Normal';
	@override String sleepTimerActive({required Object duration}) => 'Aktiv (${duration})';
	@override String get zoom => 'Zoom';
	@override String get sleepTimer => 'Sove-timer';
	@override String get audioSync => 'Lydsynkronisering';
	@override String get subtitleSync => 'Undertekstsynkronisering';
	@override String get hdr => 'HDR';
	@override String get hdrUnsupported => 'HDR er ikke tilgængelig her – denne skrivebordskompositor eller videoudgang kan ikke håndtere det.';
	@override String get hdrToneMapping => 'HDR-tonemapping';
	@override String get hdrToneMappingCompositor => 'Kompositor';
	@override String get hdrToneMappingCompositorDescription => 'Videregiv kildens HDR-metadata, og lad skrivebordskompositoren tonemappe dem.';
	@override String get hdrToneMappingPlayer => 'Afspiller';
	@override String get hdrToneMappingPlayerDescription => 'Tilpas til skærmens maksimale lysstyrke i afspilleren, og fortæl derefter kompositoren om resultatet.';
	@override String get hdrToneMappingFailed => 'Kunne ikke ændre HDR-tonemapping – den tidligere tilstand er stadig aktiv.';
	@override String get audioOutput => 'Lydoutput';
	@override String get performanceOverlay => 'Ydelsesoverlay';
	@override String get audioOutputDolbyAtmos => 'Dolby Atmos';
	@override String get audioOutputDolbyAudio => 'Dolby Audio';
	@override String get audioOutputSurround => 'Surround';
	@override String get audioOutputSpatial => 'Rumlig lyd';
	@override String get audioOutputStereo => 'Stereo';
	@override String get audioNormalization => 'Normalisér lydstyrke';
	@override String get audioNormalizationDisablesPassthrough => 'Dekoder lyd til PCM; passthrough er fra, mens dette er slået til';
	@override String get audioNormalizationStereoMix => 'Dekoder lyd til en stereomix; passthrough er fra, mens dette er slået til';
}

// Path: performanceOverlay
class _Translations$performanceOverlay$da extends Translations$performanceOverlay$en {
	_Translations$performanceOverlay$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get color => 'Farve';
	@override String get performance => 'Ydeevne';
	@override String get buffer => 'Buffer';
	@override String get app => 'App';
	@override String get decoder => 'Dekoder';
	@override String get rawDecoder => 'Rå dekoder';
	@override String get tunneling => 'Tunneling';
	@override String get passthrough => 'Passthrough';
	@override String get aspect => 'Billedformat';
	@override String get rotation => 'Rotation';
	@override String get dvSource => 'DV-kilde';
	@override String get dvPath => 'DV-sti';
	@override String get p7Conversion => 'P7-konv.';
	@override String get sampleRate => 'Samplingsrate';
	@override String get pixelFormat => 'Pixelformat';
	@override String get hwFormat => 'HW-format';
	@override String get matrix => 'Matrix';
	@override String get primaries => 'Primærfarver';
	@override String get transfer => 'Overførsel';
	@override String get renderFps => 'Gengivelses-FPS';
	@override String get displayFps => 'Skærm-FPS';
	@override String get avSync => 'A/V-synk.';
	@override String get dropped => 'Tabte';
	@override String get dvRpus => 'DV RPU’er';
	@override String get dvRpuAverage => 'DV RPU gns.';
	@override String get dvSampleAverage => 'DV-sample gns.';
	@override String get maxLuma => 'Maks. luma';
	@override String get minLuma => 'Min. luma';
	@override String get maxCll => 'MaxCLL';
	@override String get maxFall => 'MaxFALL';
	@override String get cacheUsed => 'Brugt cache';
	@override String get cacheLimit => 'Cachegrænse';
	@override String get speed => 'Hastighed';
	@override String get player => 'Afspiller';
	@override String get memory => 'Hukommelse';
	@override String get uiFps => 'UI-FPS';
	@override String get fps => 'FPS';
	@override String get decoderAndroidHw => 'Android HW';
	@override String get decoderNvidiaHw => 'NVIDIA HW';
	@override String get decoderQualcommHw => 'Qualcomm HW';
	@override String get decoderMediatekHw => 'MediaTek HW';
	@override String get decoderExynosHw => 'Exynos HW';
	@override String get decoderSoftware => 'Software';
	@override String get decoderHardware => 'Hardware';
	@override String get tunnelingActive => 'Aktiv';
	@override String dvRpuFailed({required Object converted, required Object failures}) => '${converted} (${failures} mislykkedes)';
}

// Path: externalPlayer
class _Translations$externalPlayer$da extends Translations$externalPlayer$en {
	_Translations$externalPlayer$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Ekstern afspiller';
	@override String get useExternalPlayer => 'Brug ekstern afspiller';
	@override String get useExternalPlayerDescription => 'Åbn videoer i en anden app';
	@override String get selectPlayer => 'Vælg afspiller';
	@override String get customPlayers => 'Brugerdefinerede afspillere';
	@override String get systemDefault => 'Systemstandard';
	@override String get addCustomPlayer => 'Tilføj brugerdefineret afspiller';
	@override String get playerName => 'Afspillernavn';
	@override String get playerNameHint => 'Min afspiller';
	@override String get playerCommand => 'Kommando';
	@override String get playerPackage => 'Pakkenavn';
	@override String get playerUrlScheme => 'URL-skema';
	@override String get off => 'Fra';
	@override String get launchFailed => 'Kunne ikke åbne ekstern afspiller';
	@override String appNotInstalled({required Object name}) => '${name} er ikke installeret';
	@override String get playInExternalPlayer => 'Afspil i ekstern afspiller';
}

// Path: metadataEdit
class _Translations$metadataEdit$da extends Translations$metadataEdit$en {
	_Translations$metadataEdit$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get artwork => 'Grafik';
	@override String get title => 'Titel';
	@override String get sortTitle => 'Sorteringstitel';
	@override String get originalTitle => 'Originaltitel';
	@override String get releaseDate => 'Udgivelsesdato';
	@override String get contentRating => 'Aldersgrænse';
	@override String get studio => 'Studie';
	@override String get tagline => 'Slogan';
	@override String get summary => 'Resumé';
	@override String get poster => 'Plakat';
	@override String get background => 'Baggrund';
	@override String get logo => 'Logo';
	@override String get imageUrl => 'Billed-URL';
	@override String get allEpisodes => 'Alle episoder';
	@override String get never => 'Aldrig';
	@override String get seasons => 'Sæsoner';
	@override String get show => 'Vis';
	@override String get hide => 'Skjul';
	@override String get subtitleMode => 'Automatisk valg af undertekster';
	@override String get tags => 'Tags';
	@override String get genre => 'Genre';
	@override String get director => 'Instruktør';
	@override String get writer => 'Forfatter';
	@override String get producer => 'Producer';
	@override String get country => 'Land';
	@override String get collection => 'Samling';
	@override String get label => 'Etiket';
}

// Path: matchScreen
class _Translations$matchScreen$da extends Translations$matchScreen$en {
	_Translations$matchScreen$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get match => 'Match...';
	@override String get search => 'Søg';
}

// Path: serverTasks
class _Translations$serverTasks$da extends Translations$serverTasks$en {
	_Translations$serverTasks$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Serveropgaver';
}

// Path: trakt
class _Translations$trakt$da extends Translations$trakt$en {
	_Translations$trakt$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Trakt';
	@override String get connected => 'Forbundet';
	@override String connectedAs({required Object username}) => 'Forbundet som @${username}';
	@override String get disconnectConfirm => 'Frakobl Trakt-konto?';
	@override String get disconnectConfirmBody => 'Plezy stopper med at sende hændelser til Trakt. Du kan tilslutte igen når som helst.';
	@override String get scrobble => 'Realtids-scrobbling';
	@override String get scrobbleDescription => 'Send afspil-, pause- og stop-begivenheder til Trakt under afspilning.';
	@override String get watchedSync => 'Synkroniser set-status';
	@override String get watchedSyncDescription => 'Når du markerer elementer som set i Plezy, markeres de også på Trakt.';
}

// Path: seerr
class _Translations$seerr$da extends Translations$seerr$en {
	_Translations$seerr$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Seerr';
	@override String get connectTitle => 'Forbind Seerr';
	@override String get serverUrl => 'Server-URL';
	@override String get serverUrlHelper => 'Adressen på din Seerr-instans';
	@override String get checkServer => 'Fortsæt';
	@override String get signInWithLocal => 'Brug en lokal konto';
	@override String get email => 'E-mail';
	@override String get noSignInMethods => 'Denne Seerr-instans tilbyder ingen loginmetode, som Plezy understøtter.';
	@override String get instance => 'Instans';
	@override String get disconnectConfirm => 'Afbryd forbindelsen til Seerr?';
	@override String get disconnectConfirmBody => 'Plezy glemmer denne Seerr-instans. Du kan altid oprette forbindelse igen.';
	@override String get request => 'Anmod';
	@override String get request4k => 'Anmod i 4K';
	@override String get seasons => 'Sæsoner';
	@override String get allSeasons => 'Alle sæsoner';
	@override String get advancedOptions => 'Avanceret';
	@override String get destinationServer => 'Destinationsserver';
	@override String get qualityProfile => 'Kvalitetsprofil';
	@override String get rootFolder => 'Rodmappe';
	@override String get languageProfile => 'Sprogprofil';
	@override String get tags => 'Tags';
	@override String get noTags => 'Ingen tags';
	@override String defaultOption({required Object name}) => '${name} (standard)';
	@override String get animeNote => 'Denne serie er en anime.';
	@override String get requestSubmitted => 'Anmodning sendt';
	@override String requestFailed({required Object error}) => 'Anmodning mislykkedes: ${error}';
	@override String get requestsLoadFailed => 'Kunne ikke indlæse anmodningsmuligheder';
	@override String get nothingToRequest => 'Alt er allerede tilgængeligt eller anmodet.';
	@override String get statusAvailable => 'Tilgængelig';
	@override String get statusPartiallyAvailable => 'Delvist tilgængelig';
	@override String get statusRequested => 'Anmodet';
	@override String get statusProcessing => 'Behandler';
	@override String get statusBlocklisted => 'På blokeringslisten';
	@override String couldNotReach({required Object url, required Object error}) => 'Kunne ikke nå ${url}: ${error}';
	@override String noInstanceAtUrl({required Object url, required Object status}) => 'Ingen Seerr-instans på ${url} (HTTP ${status})';
	@override String get behindAuthProxy => 'En godkendende reverse proxy (SSO eller HTTP-auth) svarede i stedet for Seerr. Plezy kan ikke logge ind gennem den: Lad Seerrs /api/v1-sti omgå proxyen for denne app, eller brug en adresse, der når Seerr direkte.';
	@override String get invalidUrl => 'Indtast en serveradresse som https://seerr.example.com';
	@override String get notInitialized => 'Denne Seerr-instans har ikke fuldført førstegangsopsætningen';
	@override String get noStoredCredentials => 'Ingen gemte loginoplysninger er tilgængelige til at logge ind igen';
	@override String get signInRejected => 'Login blev afvist';
	@override String get noSessionCookie => 'Seerr udstedte ikke en sessionscookie';
	@override String get freshCookieRejected => 'Seerr afviste den nye sessionscookie';
	@override String get noUserInformation => 'Seerr returnerede ikke brugeroplysninger';
	@override String get sessionRejectedAfterReauth => 'Sessionen blev afvist efter at være logget ind igen';
	@override String get permissionDenied => 'Seerr afviste denne handling: din konto har ikke længere den nødvendige tilladelse';
	@override String get permissionRevoked => 'Du har ikke længere tilladelse til at anmode om dette';
}

// Path: services
class _Translations$services$da extends Translations$services$en {
	_Translations$services$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Tjenester';
	@override String get hubSubtitle => 'Synkroniser dit visningsfremskridt, og anmod om nye titler.';
	@override String get integrations => 'Integrationer';
	@override String get notConnected => 'Ikke forbundet';
	@override String connectedAs({required Object username}) => 'Forbundet som @${username}';
	@override String get scrobble => 'Registrer fremgang automatisk';
	@override String get scrobbleDescription => 'Opdater din liste, når du er færdig med et afsnit eller en film.';
	@override String disconnectConfirm({required Object service}) => 'Afbryd forbindelsen til ${service}?';
	@override String disconnectConfirmBody({required Object service}) => 'Plezy stopper med at opdatere ${service}. Du kan altid oprette forbindelse igen.';
	@override String connectFailed({required Object service}) => 'Kunne ikke forbinde til ${service}. Prøv igen.';
	@override late final _Translations$services$names$da names = _Translations$services$names$da._(_root);
	@override late final _Translations$services$deviceCode$da deviceCode = _Translations$services$deviceCode$da._(_root);
	@override late final _Translations$services$oauthProxy$da oauthProxy = _Translations$services$oauthProxy$da._(_root);
	@override late final _Translations$services$pendingAuth$da pendingAuth = _Translations$services$pendingAuth$da._(_root);
	@override late final _Translations$services$libraryFilter$da libraryFilter = _Translations$services$libraryFilter$da._(_root);
}

// Path: addServer
class _Translations$addServer$da extends Translations$addServer$en {
	_Translations$addServer$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get username => 'Brugernavn';
	@override String get password => 'Adgangskode';
	@override String get signIn => 'Log ind';
	@override String get change => 'Ændr';
	@override String get required => 'Påkrævet';
	@override String couldNotReachServer({required Object error}) => 'Kunne ikke nå serveren: ${error}';
	@override String get addConnectionTitle => 'Tilføj forbindelse';
	@override String get invalidCredentials => 'Ugyldigt brugernavn eller ugyldig adgangskode';
}

// Path: common.ratingSource
class _Translations$common$ratingSource$da extends Translations$common$ratingSource$en {
	_Translations$common$ratingSource$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get critic => 'Anmeldere';
	@override String get audience => 'Publikum';
	@override String get imdb => 'IMDb';
	@override String get tmdb => 'TMDB';
	@override String get rottenTomatoes => 'Rotten Tomatoes';
	@override String get simkl => 'Simkl';
	@override String get mal => 'MyAnimeList';
	@override String get anilist => 'AniList';
	@override String get trakt => 'Trakt';
	@override String get rottenTomatoesCritic => 'Rotten Tomatoes-anmeldere';
	@override String get rottenTomatoesAudience => 'Rotten Tomatoes-publikum';
}

// Path: common.mediaKind
class _Translations$common$mediaKind$da extends Translations$common$mediaKind$en {
	_Translations$common$mediaKind$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get movie => 'Film';
	@override String get show => 'Serie';
	@override String get season => 'Sæson';
	@override String get episode => 'Afsnit';
	@override String get artist => 'Kunstner';
	@override String get album => 'Album';
	@override String get track => 'Nummer';
	@override String get collection => 'Samling';
	@override String get playlist => 'Afspilningsliste';
	@override String get clip => 'Klip';
	@override String get photo => 'Foto';
	@override String get folder => 'Mappe';
}

// Path: hotkeys.actions
class _Translations$hotkeys$actions$da extends Translations$hotkeys$actions$en {
	_Translations$hotkeys$actions$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get playPause => 'Afspil/Pause';
	@override String get volumeUp => 'Lydstyrke op';
	@override String get volumeDown => 'Lydstyrke ned';
	@override String seekForward({required Object seconds}) => 'Spol frem (${seconds}s)';
	@override String seekBackward({required Object seconds}) => 'Spol tilbage (${seconds}s)';
	@override String get fullscreenToggle => 'Slå fuldskærm til/fra';
	@override String get muteToggle => 'Slå lyd til/fra';
	@override String get subtitleToggle => 'Slå undertekster til/fra';
	@override String get audioTrackNext => 'Næste lydspor';
	@override String get subtitleTrackNext => 'Næste undertekstspor';
	@override String get chapterNext => 'Næste kapitel';
	@override String get chapterPrevious => 'Forrige kapitel';
	@override String get episodeNext => 'Næste afsnit';
	@override String get episodePrevious => 'Forrige afsnit';
	@override String get speedIncrease => 'Øg hastighed';
	@override String get speedDecrease => 'Sænk hastighed';
	@override String get speedReset => 'Nulstil hastighed';
	@override String get zoomIn => 'Zoom ind';
	@override String get zoomOut => 'Zoom ud';
	@override String get zoomReset => 'Nulstil zoom';
	@override String get subSeekNext => 'Søg til næste undertekst';
	@override String get subSeekPrev => 'Søg til forrige undertekst';
	@override String get shaderToggle => 'Slå shadere til/fra';
	@override String get skipMarker => 'Spring intro/rulletekster over';
	@override String get screenshot => 'Tag skærmbillede';
}

// Path: videoControls.pipErrors
class _Translations$videoControls$pipErrors$da extends Translations$videoControls$pipErrors$en {
	_Translations$videoControls$pipErrors$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get androidVersion => 'Kræver Android 8.0 eller nyere';
	@override String get iosVersion => 'Kræver iOS 15.0 eller nyere';
	@override String get permissionDisabled => 'Billede-i-billede er deaktiveret. Slå det til i systemindstillinger.';
	@override String get notSupported => 'Enheden understøtter ikke billede-i-billede';
	@override String get voSwitchFailed => 'Kunne ikke skifte videooutput til billede-i-billede';
	@override String get failed => 'Billede-i-billede kunne ikke starte';
	@override String get prepareFailed => 'Billede-i-billede kunne ikke forberedes';
	@override String unknown({required Object error}) => 'Der opstod en fejl: ${error}';
}

// Path: accountPreferences.subtitleModes
class _Translations$accountPreferences$subtitleModes$da extends Translations$accountPreferences$subtitleModes$en {
	_Translations$accountPreferences$subtitleModes$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get none => 'Manuelt valgt';
	@override String get defaultMode => 'Følg sporets flag';
	@override String get always => 'Altid aktiveret';
	@override String get onlyForced => 'Kun tvungne undertekster';
	@override String get smart => 'Vis ved fremmedsproget lyd';
}

// Path: accountPreferences.forcedSubtitleOptions
class _Translations$accountPreferences$forcedSubtitleOptions$da extends Translations$accountPreferences$forcedSubtitleOptions$en {
	_Translations$accountPreferences$forcedSubtitleOptions$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get onlyForced => 'Kun tvungne undertekster';
}

// Path: accountPreferences.watchedIndicatorOptions
class _Translations$accountPreferences$watchedIndicatorOptions$da extends Translations$accountPreferences$watchedIndicatorOptions$en {
	_Translations$accountPreferences$watchedIndicatorOptions$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get none => 'Aldrig';
	@override String get movies => 'Kun film';
	@override String get shows => 'Kun TV-serier';
}

// Path: libraries.tabs
class _Translations$libraries$tabs$da extends Translations$libraries$tabs$en {
	_Translations$libraries$tabs$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get recommended => 'Anbefalet';
	@override String get browse => 'Gennemse';
	@override String get collections => 'Samlinger';
	@override String get playlists => 'Playlister';
}

// Path: libraries.groupings
class _Translations$libraries$groupings$da extends Translations$libraries$groupings$en {
	_Translations$libraries$groupings$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Gruppering';
	@override String get all => 'Alle';
	@override String get movies => 'Film';
	@override String get shows => 'TV-serier';
	@override String get seasons => 'Sæsoner';
	@override String get episodes => 'Episoder';
	@override String get artists => 'Kunstnere';
	@override String get albums => 'Album';
	@override String get tracks => 'Numre';
	@override String get folders => 'Mapper';
}

// Path: libraries.filterCategories
class _Translations$libraries$filterCategories$da extends Translations$libraries$filterCategories$en {
	_Translations$libraries$filterCategories$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get genre => 'Genre';
	@override String get year => 'År';
	@override String get contentRating => 'Aldersvurdering';
	@override String get tag => 'Tag';
	@override String get unwatched => 'Usete';
}

// Path: libraries.sortLabels
class _Translations$libraries$sortLabels$da extends Translations$libraries$sortLabels$en {
	_Translations$libraries$sortLabels$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Titel';
	@override String get dateAdded => 'Tilføjet dato';
	@override String get releaseDate => 'Udgivelsesdato';
	@override String get rating => 'Vurdering';
	@override String get userRating => 'Brugerbedømmelse';
	@override String get productionYear => 'Produktionsår';
	@override String get runtime => 'Spilletid';
	@override String get startDate => 'Startdato';
	@override String get studio => 'Studie';
	@override String get dateDownloaded => 'Downloadet dato';
	@override String get size => 'Størrelse';
	@override String get library => 'Bibliotek';
}

// Path: explore.rows
class _Translations$explore$rows$da extends Translations$explore$rows$en {
	_Translations$explore$rows$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get watchlist => 'Ønskeliste';
	@override String get recommendedMovies => 'Anbefalede film';
	@override String get recommendedShows => 'Anbefalede serier';
	@override String get trendingMovies => 'Populære film lige nu';
	@override String get trendingShows => 'Populære serier lige nu';
	@override String get popularMovies => 'Populære film';
	@override String get popularShows => 'Populære serier';
	@override String get trendingAnime => 'Populær anime lige nu';
	@override String get suggestedAnime => 'Anbefalet anime';
	@override String get airingAnime => 'Bedste aktuelle anime';
	@override String get popularAnime => 'Mest populære anime';
	@override String get trending => 'Populært lige nu';
	@override String get upcomingMovies => 'Kommende film';
	@override String get upcomingShows => 'Kommende serier';
}

// Path: explore.status
class _Translations$explore$status$da extends Translations$explore$status$en {
	_Translations$explore$status$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get airing => 'Sendes';
	@override String get ended => 'Afsluttet';
	@override String get canceled => 'Aflyst';
	@override String get upcoming => 'Kommende';
}

// Path: explore.badge
class _Translations$explore$badge$da extends Translations$explore$badge$en {
	_Translations$explore$badge$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String rankPopular({required Object n}) => '#${n} populær';
	@override String rankAiring({required Object n}) => '#${n} på luften';
	@override String rankRated({required Object n}) => '#${n} bedømt';
	@override String rankTrending({required Object n}) => '#${n} populær lige nu';
	@override String rankSeasonal({required Object n, required Object season}) => '#${n} i ${season}';
	@override String watchingNow({required Object n}) => '${n} ser med';
	@override String get available => 'Tilgængelig';
	@override String get partiallyAvailable => 'Delvist tilgængelig';
	@override String get availableIn4k => '4K tilgængelig';
	@override String get requested => 'Anmodet';
	@override String get pendingApproval => 'Afventer godkendelse';
	@override String get processing => 'Behandles';
	@override String get declined => 'Afvist';
	@override String get requestFailed => 'Anmodningen mislykkedes';
	@override String get requested4k => '4K anmodet';
	@override String seasonsAvailable({required Object available, required Object total}) => '${available}/${total} sæsoner';
	@override String nextEpisodeIn({required Object episode, required Object duration}) => 'Afsnit ${episode} om ${duration}';
	@override String nextAiringIn({required Object duration}) => 'Næste om ${duration}';
	@override String episodesShort({required Object n}) => '${n} afsnit';
	@override String minutesPerEpisode({required Object n}) => '${n} min/afsnit';
	@override String get adult => '18+';
}

// Path: explore.stats
class _Translations$explore$stats$da extends Translations$explore$stats$en {
	_Translations$explore$stats$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String listed({required Object n}) => '${n} opført';
	@override String viewersDay({required Object n}) => '${n} så det i dag';
	@override String viewersWeek({required Object n}) => '${n} så det denne uge';
	@override String viewersMonth({required Object n}) => '${n} så det denne måned';
	@override String viewersYear({required Object n}) => '${n} så det i år';
	@override String viewersAllTime({required Object n}) => '${n} seere';
	@override String planning({required Object n}) => '${n} planlægger at se det';
	@override String favorited({required Object n}) => '${n} favoritter';
	@override String dropRate({required Object percent}) => '${percent} droppede det';
	@override String comments({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n,
		one: '${n} kommentar',
		other: '${n} kommentarer',
	);
	@override String votes({required Object n}) => '${n} stemmer';
	@override String watching({required Object n}) => '${n} ser det';
	@override String completed({required Object n}) => '${n} færdigset';
	@override String onHold({required Object n}) => '${n} på pause';
	@override String dropped({required Object n}) => '${n} droppede';
}

// Path: explore.season
class _Translations$explore$season$da extends Translations$explore$season$en {
	_Translations$explore$season$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get winter => 'Vinter';
	@override String get spring => 'Forår';
	@override String get summer => 'Sommer';
	@override String get fall => 'Efterår';
	@override String withYear({required Object season, required Object year}) => '${season} ${year}';
}

// Path: explore.format
class _Translations$explore$format$da extends Translations$explore$format$en {
	_Translations$explore$format$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get tv => 'TV';
	@override String get tvShort => 'TV-kort';
	@override String get movie => 'Film';
	@override String get special => 'Special';
	@override String get ova => 'OVA';
	@override String get ona => 'ONA';
	@override String get music => 'Musik';
	@override String get other => 'Andet';
}

// Path: explore.sourceMaterial
class _Translations$explore$sourceMaterial$da extends Translations$explore$sourceMaterial$en {
	_Translations$explore$sourceMaterial$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get original => 'Original';
	@override String get manga => 'Manga';
	@override String get lightNovel => 'Light novel';
	@override String get novel => 'Roman';
	@override String get visualNovel => 'Visual novel';
	@override String get game => 'Spil';
	@override String get webComic => 'Webtegneserie';
	@override String get musicRelease => 'Musik';
	@override String get otherMedia => 'Andet';
}

// Path: explore.creditRole
class _Translations$explore$creditRole$da extends Translations$explore$creditRole$en {
	_Translations$explore$creditRole$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get director => 'Instruktør';
	@override String get writer => 'Forfatter';
	@override String get producer => 'Producer';
	@override String get creator => 'Skaber';
	@override String get composer => 'Komponist';
}

// Path: explore.relation
class _Translations$explore$relation$da extends Translations$explore$relation$en {
	_Translations$explore$relation$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get prequel => 'Prequel';
	@override String get sequel => 'Sequel';
	@override String get sideStory => 'Bihistorie';
	@override String get spinOff => 'Spin-off';
	@override String get alternativeVersion => 'Alternativ version';
	@override String get summary => 'Resumé';
	@override String get parentStory => 'Hovedhistorie';
	@override String get adaptation => 'Adaption';
	@override String get other => 'Relateret';
}

// Path: explore.detail
class _Translations$explore$detail$da extends Translations$explore$detail$en {
	_Translations$explore$detail$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get originalTitle => 'Originaltitel';
	@override String get alsoKnownAs => 'Også kendt som';
	@override String get studios => 'Studier';
	@override String get country => 'Land';
	@override String get language => 'Sprog';
	@override String get released => 'Udgivet';
	@override String get physicalRelease => 'På disk';
	@override String get ended => 'Afsluttet';
	@override String addedOn({required Object date}) => 'Tilføjet ${date}';
	@override String get yourRating => 'Din bedømmelse';
	@override String get budget => 'Budget';
	@override String get revenue => 'Billetindtægter';
	@override String get contentAdvisory => 'Aldersvejledning';
	@override String get tags => 'Tags';
	@override String get revealSpoilerTags => 'Vis spoilertags';
	@override String get links => 'Links';
	@override String get watchOn => 'Se på';
	@override String get watchTrailer => 'Se trailer';
	@override String openOn({required Object site}) => 'Åbn på ${site}';
	@override String get crew => 'Crew';
	@override String get ratings => 'Bedømmelser';
	@override String get schedule => 'Program';
	@override String recommendedByUsers({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n,
		one: 'Anbefalet af ${n} bruger',
		other: 'Anbefalet af ${n} brugere',
	);
	@override String recommendedBy({required Object who}) => 'Anbefalet af ${who}';
	@override String favoritedBy({required Object who}) => 'Favorit hos ${who}';
	@override String unairedEpisodes({required Object n}) => '${n} ikke sendt endnu';
	@override String recommendedByPercent({required Object percent}) => 'Anbefalet af ${percent} af seerne';
	@override String get relatedTitles => 'Relaterede titler';
	@override String get background => 'Baggrund';
}

// Path: music.discography
class _Translations$music$discography$da extends Translations$music$discography$en {
	_Translations$music$discography$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get singlesAndEps => 'Singler og EP\'er';
	@override String get live => 'Live';
	@override String get compilations => 'Opsamlinger';
}

// Path: watchTogether.errors
class _Translations$watchTogether$errors$da extends Translations$watchTogether$errors$en {
	_Translations$watchTogether$errors$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get timedOut => 'Relayserveren svarede ikke i tide';
	@override String get connectionLost => 'Forbindelsen blev lukket, før sessionen var klar';
	@override String get invalidRelayResponse => 'Relayserveren sendte et uventet svar';
	@override String get sessionEnded => 'Værten afsluttede sessionen';
	@override String get sessionUnavailable => 'Kan ikke genoptage denne session. Deltag i eller opret et rum for at fortsætte.';
}

// Path: downloads.backgroundWarning
class _Translations$downloads$backgroundWarning$da extends Translations$downloads$backgroundWarning$en {
	_Translations$downloads$backgroundWarning$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get bannerBlocked => 'Downloads stopper, når du forlader appen';
	@override String get bannerDegraded => 'Downloads i baggrunden kan være begrænsede';
	@override String get bannerAction => 'Detaljer';
	@override String get sheetTitle => 'Downloads i baggrunden er blokeret';
	@override String get sheetTitleDegraded => 'Downloads i baggrunden kan være begrænsede';
	@override String get sheetIntro => 'Android forhindrer Plezy i at downloade stabilt i baggrunden.';
	@override String get sheetIntroDegraded => 'Din enhed begrænser, hvornår Plezy kan downloade i baggrunden.';
	@override String get reasonBackgroundRestricted => 'Plezys baggrundsaktivitet er begrænset. Indstil batteriforbruget eller baggrundsaktiviteten til "Ubegrænset".';
	@override String get reasonStandbyRestricted => 'Android har sat Plezy i begrænset standbytilstand. Indstil batteriforbruget til "Ubegrænset".';
	@override String get reasonDownloadChannelBlocked => 'Notifikationer om downloads er slået fra, så status og betjeningsknapper muligvis ikke er tilgængelige.';
	@override String get reasonNotificationsDisabled => 'Notifikationer er slået fra. På Android 13 eller nyere er de nødvendige ved lange downloads i baggrunden.';
	@override String get reasonDataSaver => 'Datasparefunktionen er slået til, hvilket blokerer downloads i baggrunden via mobildata. Downloads bør stadig køre på Wi-Fi.';
	@override String get reasonOemUnknown => 'Downloads stoppede gentagne gange, mens Plezy var i baggrunden. Tjek Plezys indstillinger for batteriforbrug eller baggrundsaktivitet.';
	@override String get openSettings => 'Åbn indstillinger';
	@override String get stillNotWorking => 'Enhedsspecifik hjælp';
	@override String get stillNotWorkingDescription => 'Se vejledningen til din enhed, eller send en logfil fra Indstillinger › Vis logfiler, hvis problemet fortsætter.';
	@override String get dialogTitle => 'Downloads bliver muligvis ikke færdige';
	@override String get dialogDownloadAnyway => 'Download alligevel';
	@override String get dialogFixFirst => 'Løs dette først';
	@override String get statusTile => 'Downloads i baggrunden';
	@override String get statusOk => 'Må køre i baggrunden';
	@override String get statusBlocked => 'Blokeret af systemindstillinger';
	@override String get statusDegraded => 'Begrænset af systemindstillinger';
	@override String get statusUnknown => 'Endnu ikke kontrolleret';
	@override String get settingsUnavailable => 'Kunne ikke åbne systemindstillingerne på denne enhed';
	@override String get linkUnavailable => 'Kunne ikke åbne dontkillmyapp.com på denne enhed';
}

// Path: downloads.groupings
class _Translations$downloads$groupings$da extends Translations$downloads$groupings$en {
	_Translations$downloads$groupings$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get library => 'Bibliotek';
}

// Path: companionRemote.session
class _Translations$companionRemote$session$da extends Translations$companionRemote$session$en {
	_Translations$companionRemote$session$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get startingServer => 'Starter fjernbetjeningsserver...';
	@override String get hostAddress => 'Værtsadresse';
	@override String get connected => 'Forbundet';
	@override String get serverRunning => 'Fjernbetjeningsserver aktiv';
	@override String get serverStopped => 'Fjernbetjeningsserver stoppet';
	@override String get serverRunningDescription => 'Mobile enheder på dit netværk kan oprette forbindelse til denne app';
	@override String get serverStoppedDescription => 'Start serveren for at tillade mobilenheder at oprette forbindelse';
	@override String get usePhoneToControl => 'Brug din mobilenhed til at styre denne app';
	@override String get startServer => 'Start serveren';
	@override String get stopServer => 'Stop serveren';
	@override String get minimize => 'Minimér';
	@override String get manualAddressHint => 'Manuel forbindelsesadresse:';
}

// Path: companionRemote.pairing
class _Translations$companionRemote$pairing$da extends Translations$companionRemote$pairing$en {
	_Translations$companionRemote$pairing$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get hostAddressHint => '192.168.1.100:48632';
	@override String get connecting => 'Opretter forbindelse...';
	@override String get searchingForDevices => 'Søger efter enheder...';
	@override String get noDevicesFound => 'Ingen enheder fundet på dit netværk';
	@override String get noDevicesHint => 'Åbn Plezy på din computer, og brug det samme Wi-Fi-netværk';
	@override String get availableDevices => 'Tilgængelige enheder';
	@override String get manualConnection => 'Manuel forbindelse';
	@override String get validationHostRequired => 'Angiv en værtsadresse';
	@override String get validationHostFormat => 'Format skal være IP:port (f.eks. 192.168.1.100:48632)';
	@override String get connectionTimedOut => 'Forbindelsen fik timeout. Brug samme netværk på begge enheder.';
	@override String get sessionNotFound => 'Enhed ikke fundet. Sørg for, at Plezy kører på værten.';
	@override String failedToConnect({required Object error}) => 'Kunne ikke oprette forbindelse: ${error}';
}

// Path: companionRemote.remote
class _Translations$companionRemote$remote$da extends Translations$companionRemote$remote$en {
	_Translations$companionRemote$remote$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get disconnectConfirm => 'Vil du afbryde forbindelsen til fjernsessionen?';
	@override String get reconnecting => 'Genopretter forbindelse...';
	@override String attemptOf({required Object current}) => 'Forsøg ${current} af 5';
	@override String get retryNow => 'Prøv igen nu';
	@override String get tabRemote => 'Fjernbetjening';
	@override String get tabPlay => 'Afspil';
	@override String get tabMore => 'Mere';
	@override String get menu => 'Menu';
	@override String get tabNavigation => 'Fanenavigation';
	@override String get tabDiscover => 'Opdag';
	@override String get tabLibraries => 'Biblioteker';
	@override String get tabSearch => 'Søg';
	@override String get tabDownloads => 'Downloads';
	@override String get tabSettings => 'Indstillinger';
	@override String get previous => 'Forrige';
	@override String get playPause => 'Afspil/Pause';
	@override String get next => 'Næste';
	@override String get seekBack => 'Spol tilbage';
	@override String get stop => 'Stop';
	@override String get seekForward => 'Spol frem';
	@override String get volume => 'Lydstyrke';
	@override String get volumeDown => 'Ned';
	@override String get volumeUp => 'Op';
	@override String get fullscreen => 'Fuldskærm';
	@override String get subtitles => 'Undertekster';
	@override String get audio => 'Lyd';
	@override String get searchHint => 'Søg på desktop...';
}

// Path: companionRemote.errors
class _Translations$companionRemote$errors$da extends Translations$companionRemote$errors$en {
	_Translations$companionRemote$errors$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get noNetworkInterface => 'Ingen netværksgrænseflade fundet';
	@override String get authenticationFailed => 'Godkendelse mislykkedes';
	@override String serverStartFailed({required Object error}) => 'Fjernbetjeningsserveren kunne ikke startes: ${error}';
	@override String commandFailed({required Object error}) => 'Kunne ikke sende fjernkommando: ${error}';
	@override String get joinTimedOut => 'Tidsgrænse for deltagelse i session overskredet';
	@override String get failedToConnectAnyAddress => 'Kunne ikke oprette forbindelse til nogen adresse';
	@override String connectionLostAfterAttempts({required Object attempts}) => 'Forbindelse mistet efter ${attempts} forsøg';
	@override String get connectionLost => 'Forbindelse mistet';
}

// Path: services.names
class _Translations$services$names$da extends Translations$services$names$en {
	_Translations$services$names$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get mal => 'MyAnimeList';
	@override String get anilist => 'AniList';
	@override String get simkl => 'Simkl';
	@override String get seerr => 'Seerr';
	@override String get mdblist => 'MDBList';
}

// Path: services.deviceCode
class _Translations$services$deviceCode$da extends Translations$services$deviceCode$en {
	_Translations$services$deviceCode$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String title({required Object service}) => 'Aktiver Plezy på ${service}';
	@override String get instructions => 'Scan QR-koden, eller gå til adressen nedenfor, og indtast denne kode:';
	@override String openToActivate({required Object service}) => 'Åbn ${service} for at aktivere';
	@override String get copyCode => 'Kopiér aktiveringskode';
	@override String get waitingForAuthorization => 'Venter på godkendelse…';
	@override String get codeCopied => 'Kode kopieret';
}

// Path: services.oauthProxy
class _Translations$services$oauthProxy$da extends Translations$services$oauthProxy$en {
	_Translations$services$oauthProxy$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String title({required Object service}) => 'Log ind på ${service}';
	@override String get body => 'Scan denne QR-kode, eller åbn URL\'en på en enhed.';
	@override String openToSignIn({required Object service}) => 'Åbn ${service} for at logge ind';
}

// Path: services.pendingAuth
class _Translations$services$pendingAuth$da extends Translations$services$pendingAuth$en {
	_Translations$services$pendingAuth$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get copyUrl => 'Kopiér login-URL';
	@override String get urlCopied => 'URL kopieret';
}

// Path: services.libraryFilter
class _Translations$services$libraryFilter$da extends Translations$services$libraryFilter$en {
	_Translations$services$libraryFilter$da._(TranslationsDa root) : this._root = root, super.internal(root);

	final TranslationsDa _root; // ignore: unused_field

	// Translations
	@override String get title => 'Bibliotekfilter';
	@override String get subtitleAllSyncing => 'Synkroniserer alle biblioteker';
	@override String get subtitleNoneSyncing => 'Intet synkroniseres';
	@override String subtitleBlocked({required Object count}) => '${count} blokeret';
	@override String subtitleAllowed({required Object count}) => '${count} tilladt';
	@override String get mode => 'Filtertilstand';
	@override String get modeBlacklist => 'Blokliste';
	@override String get modeWhitelist => 'Tilladelsesliste';
	@override String get modeHintBlacklist => 'Synkroniser alle biblioteker undtagen dem, du markerer nedenfor.';
	@override String get modeHintWhitelist => 'Synkroniser kun de biblioteker, du markerer nedenfor.';
	@override String get libraries => 'Biblioteker';
	@override String get noLibraries => 'Ingen biblioteker tilgængelige';
}

/// The flat map containing all translations for locale <da>.
/// Only for edge cases! For simple maps, use the map function of this library.
///
/// The Dart AOT compiler has issues with very large switch statements,
/// so the map is split into smaller functions (512 entries each).
extension on TranslationsDa {
	dynamic _flatMapFunction(String path) {
		return switch (path) {
			'app.title' => 'Plezy',
			'auth.localDataRecoveryRequired' => 'Plezy kunne ikke gendanne lokale loginoplysninger og ventende afspilningsdata på en sikker måde. Log ind igen.',
			'common.cancel' => 'Annuller',
			'common.save' => 'Gem',
			'common.close' => 'Luk',
			'common.clear' => 'Ryd',
			'common.reset' => 'Nulstil',
			'common.later' => 'Senere',
			'common.submit' => 'Indsend',
			'common.retry' => 'Prøv igen',
			'common.logout' => 'Log ud',
			'common.unknown' => 'Ukendt',
			'common.refresh' => 'Opdater',
			'common.yes' => 'Ja',
			'common.no' => 'Nej',
			'common.delete' => 'Slet',
			'common.edit' => 'Rediger',
			'common.shuffle' => 'Bland',
			'common.addTo' => 'Tilføj til...',
			'common.createNew' => 'Opret ny',
			'common.connect' => 'Forbind',
			'common.disconnect' => 'Afbryd',
			'common.play' => 'Afspil',
			'common.pause' => 'Pause',
			'common.resume' => 'Genoptag',
			'common.error' => 'Fejl',
			'common.search' => 'Søg',
			'common.home' => 'Hjem',
			'common.back' => 'Tilbage',
			'common.settings' => 'Indstillinger',
			'common.mute' => 'Lydløs',
			'common.ok' => 'OK',
			'common.off' => 'Fra',
			'common.options' => 'Valgmuligheder',
			'common.seasonNumber' => ({required Object number}) => 'Sæson ${number}',
			'common.episodeNumberTitle' => ({required Object number, required Object title}) => 'Episode ${number} – ${title}',
			'common.chapterNumber' => ({required Object number}) => 'Kapitel ${number}',
			'common.reconnect' => 'Genopret forbindelse',
			'common.viewAll' => 'Vis alle',
			'common.checkingNetwork' => 'Tjekker netværk...',
			'common.loadingServers' => 'Indlæser servere...',
			'common.connectingToServers' => 'Forbinder til servere...',
			'common.startingOfflineMode' => 'Starter offlinetilstand...',
			'common.loading' => 'Indlæser...',
			'common.fullscreen' => 'Fuldskærm',
			'common.exitFullscreen' => 'Forlad fuldskærm',
			'common.pressBackAgainToExit' => 'Tryk på tilbage igen for at afslutte',
			'common.ratingSource.critic' => 'Anmeldere',
			'common.ratingSource.audience' => 'Publikum',
			'common.ratingSource.imdb' => 'IMDb',
			'common.ratingSource.tmdb' => 'TMDB',
			'common.ratingSource.rottenTomatoes' => 'Rotten Tomatoes',
			'common.ratingSource.simkl' => 'Simkl',
			'common.ratingSource.mal' => 'MyAnimeList',
			'common.ratingSource.anilist' => 'AniList',
			'common.ratingSource.trakt' => 'Trakt',
			'common.ratingSource.rottenTomatoesCritic' => 'Rotten Tomatoes-anmeldere',
			'common.ratingSource.rottenTomatoesAudience' => 'Rotten Tomatoes-publikum',
			'common.notAvailable' => 'N/A',
			'common.url' => 'URL',
			'common.letterKeys' => 'ABC',
			'common.mediaKind.movie' => 'Film',
			'common.mediaKind.show' => 'Serie',
			'common.mediaKind.season' => 'Sæson',
			'common.mediaKind.episode' => 'Afsnit',
			'common.mediaKind.artist' => 'Kunstner',
			'common.mediaKind.album' => 'Album',
			'common.mediaKind.track' => 'Nummer',
			'common.mediaKind.collection' => 'Samling',
			'common.mediaKind.playlist' => 'Afspilningsliste',
			'common.mediaKind.clip' => 'Klip',
			'common.mediaKind.photo' => 'Foto',
			'common.mediaKind.folder' => 'Mappe',
			'screens.licenses' => 'Licenser',
			'screens.switchProfile' => 'Skift profil',
			'screens.subtitleStyling' => 'Undertekststil',
			'screens.mpvConfig' => 'mpv.conf',
			'screens.logs' => 'Logfiler',
			'update.available' => 'Opdatering tilgængelig',
			'update.versionAvailable' => ({required Object version}) => 'Version ${version} er tilgængelig',
			'update.currentVersion' => ({required Object version}) => 'Nuværende: ${version}',
			'update.skipVersion' => 'Spring denne version over',
			'update.viewRelease' => 'Vis udgivelse',
			'update.latestVersion' => 'Du har den nyeste version',
			'update.checkFailed' => 'Kunne ikke søge efter opdateringer',
			'settings.title' => 'Indstillinger',
			'settings.supportDeveloper' => 'Støt Plezy',
			'settings.supportDeveloperDescription' => 'Doner via Liberapay for at finansiere udviklingen',
			'settings.language' => 'Sprog',
			'settings.theme' => 'Tema',
			'settings.appearance' => 'Udseende',
			'settings.videoPlayback' => 'Videoafspilning',
			'settings.videoPlaybackDescription' => 'Konfigurer afspilningsadfærd',
			'settings.advanced' => 'Avanceret',
			'settings.episodePosterMode' => 'Episodeplakatstil',
			'settings.seriesPoster' => 'Serieplakat',
			'settings.seasonPoster' => 'Sæsonplakat',
			'settings.episodeThumbnail' => 'Miniature',
			'settings.showHeroSectionDescription' => 'Vis karrusel med udvalgt indhold på startskærmen',
			'settings.secondsLabel' => 'Sekunder',
			'settings.minutesLabel' => 'Minutter',
			'settings.secondsShort' => 's',
			'settings.minutesShort' => 'm',
			'settings.durationHint' => ({required Object min, required Object max}) => 'Indtast varighed (${min}-${max})',
			'settings.systemTheme' => 'System',
			'settings.lightTheme' => 'Lys',
			'settings.darkTheme' => 'Mørk',
			'settings.oledTheme' => 'OLED',
			'settings.libraryDensity' => 'Bibliotekstæthed',
			'settings.displayScale' => 'Skalering',
			'settings.compact' => 'Kompakt',
			'settings.comfortable' => 'Komfortabel',
			'settings.gridSpacing' => 'Gitterafstand',
			'settings.gridSpacingTight' => 'Tæt',
			'settings.gridSpacingNormal' => 'Normal',
			'settings.gridSpacingSpacious' => 'Rummelig',
			'settings.tvCornerSpotlightBackdrop' => 'Fremhævet baggrundsbillede i hjørnet',
			'settings.tvCornerSpotlightBackdropDescription' => 'Vis fremhævet grafik i øverste højre hjørne i stedet for at fylde skærmen',
			'settings.viewMode' => 'Visningstilstand',
			'settings.gridView' => 'Gitter',
			'settings.listView' => 'Liste',
			'settings.showHeroSection' => 'Vis udvalgt indhold',
			'settings.continueWatchingAction' => 'Handling for "Fortsæt med at se"',
			'settings.continueWatchingPlay' => 'Afspil',
			'settings.continueWatchingDetails' => 'Åbn detaljer',
			'settings.episodeAction' => 'Handling for afsnit',
			'settings.episodePlay' => 'Afspil',
			'settings.episodeDetails' => 'Åbn detaljer',
			'settings.useGlobalHubs' => 'Brug startlayout',
			'settings.useGlobalHubsDescription' => 'Vis samlet startsideindhold. Brug ellers biblioteksanbefalinger.',
			'settings.showServerNameOnHubs' => 'Vis servernavn på hubber',
			'settings.showServerNameOnHubsDescription' => 'Vis altid servernavne i titler på hubber.',
			'settings.groupLibrariesByServer' => 'Grupper biblioteker efter server',
			'settings.groupLibrariesByServerDescription' => 'Gruppér bibliotekerne i sidepanelet under hver medieserver.',
			'settings.alwaysKeepSidebarOpen' => 'Hold altid sidepanelet åbent',
			'settings.alwaysKeepSidebarOpenDescription' => 'Sidepanelet forbliver udvidet, og indholdsområdet tilpasser sig',
			'settings.showUnwatchedCount' => 'Vis antal usete',
			'settings.showUnwatchedCountDescription' => 'Vis antal usete episoder på serier og sæsoner',
			'settings.showWatchedIndicators' => 'Vis set-markeringer',
			'settings.showWatchedIndicatorsDescription' => 'Vis et flueben på sete film, serier og episoder',
			'settings.showEpisodeNumberOnCards' => 'Vis episodenummer på kort',
			'settings.showEpisodeNumberOnCardsDescription' => 'Vis sæson- og episodenummer på episodekort',
			'settings.showSeasonPostersOnTabs' => 'Vis sæsonplakater på faner',
			'settings.showSeasonPostersOnTabsDescription' => 'Vis hver sæsons plakat over dens fane',
			'settings.tvFullCardLayout' => 'TV-kort med billeder over hele fladen',
			'settings.tvFullCardLayoutDescription' => 'Brug TV-kort, der kun viser billeder, med skuespillernavnene ovenpå',
			'settings.focusGlow' => 'Fokusglød',
			'settings.focusGlowDescription' => 'Vis en blød glød omkring det fokuserede kort',
			'settings.visualEffects' => 'Visuelle effekter',
			'settings.visualEffectsAuto' => 'Automatisk',
			'settings.visualEffectsAutoDescription' => 'Reducer automatisk effekter på enheder med lav ydeevne',
			'settings.visualEffectsFull' => 'Fuld',
			'settings.visualEffectsReduced' => 'Reduceret',
			'settings.visualEffectsReducedDescription' => 'Færre animationer og illustrationer i lavere opløsning',
			'settings.hideSpoilers' => 'Skjul spoilere for usete episoder',
			'settings.hideSpoilersDescription' => 'Slør miniaturebilleder og beskrivelser for usete episoder',
			'settings.playerBackend' => 'Afspillermotor',
			'settings.exoPlayer' => 'ExoPlayer',
			'settings.mpv' => 'mpv',
			'settings.hardwareDecoding' => 'Hardwaredekodning',
			'settings.hardwareDecodingDescription' => 'Brug hardwareacceleration, når den er tilgængelig',
			'settings.playbackBuffer' => 'Afspilningsbuffer',
			'settings.playbackBufferAuto' => 'Auto (anbefalet)',
			'settings.playbackBufferLarge' => 'Stor',
			'settings.playbackBufferExtraLarge' => 'Ekstra stor',
			'settings.playbackBufferDescription' => 'Bufrer mere mod ustabile forbindelser. Begrænses også af bufferstørrelsen.',
			'settings.defaultQualityTitle' => 'Standardkvalitet',
			'settings.cellularQualityTitle' => 'Standardkvalitet på mobildata',
			'settings.cellularQualitySameAsDefault' => 'Samme som standardkvalitet',
			'settings.directPlayCoveredQuality' => 'Afspil mindre videoer i original kvalitet',
			'settings.directPlayCoveredQualityDescription' => 'Afspil videoer, der allerede er inden for kvalitetsgrænsen, direkte i stedet for at transkode dem',
			'settings.videoCodecs' => 'Videocodecs',
			'settings.videoCodecsDescription' => 'Codecs uden flueben transkodes af serveren',
			'settings.videoCodecsAlwaysAccepted' => 'Accepteres altid',
			'settings.musicQualityTitle' => 'Musikkvalitet',
			'settings.subtitleStyling' => 'Undertekststil',
			'settings.subtitleStylingDescription' => 'Tilpas underteksters udseende',
			'settings.smallSkipDuration' => 'Kort spring',
			'settings.largeSkipDuration' => 'Langt spring',
			'settings.rewindOnResume' => 'Spol tilbage ved genoptagelse',
			'settings.secondsUnit' => ({required Object seconds}) => '${seconds} sekunder',
			'settings.defaultSleepTimer' => 'Standard-sovetimer',
			'settings.minutesUnit' => ({required Object minutes}) => '${minutes} minutter',
			'settings.rememberTrackSelections' => 'Husk sporvalg for hver serie/film',
			'settings.rememberTrackSelectionsDescription' => 'Husk valget af lyd og undertekster for hver titel',
			'settings.followServerTrackSelections' => 'Brug serverens sporvalg for hvert afsnit',
			'settings.followServerTrackSelectionsDescription' => 'Ved afsnitsskift anvendes lyden og underteksterne valgt på serveren i stedet for at videreføre det aktuelle valg',
			'settings.resumeMusicOnLaunch' => 'Husk musiksession',
			'settings.resumeMusicOnLaunchDescription' => 'Åbn den seneste sang på pause der, hvor den slap, når appen starter',
			'settings.showChapterMarkersOnTimeline' => 'Vis kapitelmarkører på tidslinjen',
			'settings.showChapterMarkersOnTimelineDescription' => 'Opdel tidslinjen ved kapitelgrænser',
			'settings.specialsOrdering' => 'Specialafsnit i episoderekkefølge',
			'settings.specialsOrderingDescription' => 'Hvor specialafsnit afspilles i seriens visningsrækkefølge',
			'settings.specialsOrderingServer' => 'Følg serverrækkefølgen',
			'settings.specialsOrderingAirDate' => 'Indflet efter udsendelsesdato',
			'settings.specialsOrderingLast' => 'Efter almindelige sæsoner',
			'settings.clickVideoTogglesPlayback' => 'Klik på videoen for at skifte mellem afspilning og pause',
			'settings.clickVideoTogglesPlaybackDescription' => 'Klik på videoen for at afspille eller sætte på pause i stedet for at vise betjeningsknapperne.',
			'settings.videoPlayerControls' => 'Videoafspillerkontroller',
			'settings.keyboardShortcuts' => 'Tastaturgenveje',
			'settings.keyboardShortcutsDescription' => 'Tilpas tastaturgenveje',
			'settings.videoPlayerNavigation' => 'Videoafspillernavigation',
			'settings.videoPlayerNavigationDescription' => 'Brug piletaster til at navigere videoafspillerkontroller',
			'settings.watchTogetherRelay' => 'Relayserver til Se sammen',
			'settings.watchTogetherRelayDescription' => 'Angiv en brugerdefineret relayserver. Alle skal bruge den samme server.',
			'settings.watchTogetherRelayHint' => 'https://min-relay.eksempel.dk',
			'settings.watchTogetherRelayInvalid' => 'Angiv en gyldig basis-URL til en HTTP- eller HTTPS-relayserver.',
			'settings.crashReporting' => 'Fejlrapportering',
			'settings.crashReportingDescription' => 'Send fejlrapporter for at hjælpe med at forbedre appen',
			'settings.debugLogging' => 'Fejlfindingslogning',
			'settings.debugLoggingDescription' => 'Aktiver detaljeret logning til fejlfinding',
			'settings.viewLogs' => 'Vis logfiler',
			'settings.viewLogsDescription' => 'Vis programmets logfiler',
			'settings.clearImageCache' => 'Ryd billedcache',
			'settings.clearImageCacheDescription' => 'Ryd cachelagrede covers og thumbnails. Billeder kan indlæse langsommere, indtil de downloades igen.',
			'settings.clearImageCacheSuccess' => 'Billedcachen er ryddet',
			'settings.resetSettings' => 'Nulstil indstillinger',
			'settings.resetSettingsDescription' => 'Gendan standardindstillinger. Dette kan ikke fortrydes.',
			'settings.resetSettingsSuccess' => 'Indstillinger nulstillet',
			'settings.backup' => 'Sikkerhedskopi',
			'settings.exportSettings' => 'Eksportér indstillinger',
			'settings.exportSettingsDescription' => 'Gem dine præferencer i en fil',
			'settings.exportSettingsSuccess' => 'Indstillinger eksporteret',
			'settings.importSettings' => 'Importér indstillinger',
			'settings.importSettingsDescription' => 'Gendan præferencer fra en fil',
			'settings.importSettingsConfirm' => 'Dette vil erstatte dine nuværende indstillinger. Fortsæt?',
			'settings.importSettingsSuccess' => 'Indstillinger importeret',
			'settings.importSettingsInvalidFile' => 'Denne fil er ikke en gyldig eksport af Plezy-indstillinger',
			'settings.importSettingsNoUser' => 'Log ind før import af indstillinger',
			'settings.shortcutsReset' => 'Genveje nulstillet til standard',
			'settings.about' => 'Om',
			'settings.aboutDescription' => 'App-information og licenser',
			'settings.updates' => 'Opdateringer',
			'settings.updateAvailable' => 'Opdatering tilgængelig',
			'settings.checkForUpdates' => 'Søg efter opdateringer',
			'settings.autoCheckUpdatesOnStartup' => 'Søg automatisk efter opdateringer ved opstart',
			'settings.autoCheckUpdatesOnStartupDescription' => 'Giv besked, når en opdatering er tilgængelig ved start',
			'settings.validationErrorEnterNumber' => 'Indtast et gyldigt tal',
			'settings.validationErrorDuration' => ({required Object min, required Object max, required Object unit}) => 'Varigheden skal være mellem ${min} og ${max} ${unit}',
			'settings.shortcutAlreadyAssigned' => ({required Object action}) => 'Genvejen er allerede tildelt ${action}',
			'settings.shortcutUpdated' => ({required Object action}) => 'Genvejen for ${action} er opdateret',
			'settings.saveFailed' => 'Ændringerne kunne ikke gemmes. Prøv igen.',
			'settings.autoPlayAndSkip' => 'Autoafspilning og spring',
			'settings.autoPlayNextEpisode' => 'Autoafspil næste afsnit',
			'settings.autoPlayNextEpisodeDescription' => 'Start automatisk næste afsnit, når et afsnit slutter',
			'settings.shuffleStartsFromBeginning' => 'Blandet afspilning starter forfra',
			'settings.shuffleStartsFromBeginningDescription' => 'Start hvert afsnit forfra ved blandet afspilning i stedet for at genoptage',
			'settings.playNextCountdown' => 'Nedtælling til næste afsnit',
			'settings.playNextCountdownImmediate' => 'Afspil med det samme',
			'settings.skipIntroMode' => 'Spring intro over',
			'settings.skipIntroModeOffDescription' => 'Afspil introer normalt uden en spring-knap',
			'settings.skipIntroModeButtonDescription' => 'Vis en spring-knap, når en intro starter',
			'settings.skipIntroModeAutoDescription' => 'Spring introer automatisk over efter forsinkelsen nedenfor',
			'settings.skipCreditsMode' => 'Spring rulletekster over',
			'settings.skipCreditsModeOffDescription' => 'Afspil rulletekster normalt uden en spring-knap',
			'settings.skipCreditsModeButtonDescription' => 'Vis en spring-knap, når rulleteksterne starter',
			'settings.skipCreditsModeAutoDescription' => 'Spring rulletekster automatisk over, og afspil næste afsnit',
			'settings.skipMarkerModeOff' => 'Fra',
			'settings.skipMarkerModeButton' => 'Vis knap',
			'settings.skipMarkerModeAuto' => 'Automatisk',
			'settings.forceSkipMarkerFallback' => 'Tving reservemarkører',
			'settings.autoSkipDelay' => 'Forsinkelse ved automatisk spring',
			'settings.autoSkipDelayDescription' => ({required Object seconds}) => 'Vent ${seconds} sekunder, før der springes automatisk',
			'settings.introPattern' => 'Intromarkørmønster',
			'settings.introPatternDescription' => 'Regulært udtryk til at genkende intromarkører i kapiteltitler',
			'settings.creditsPattern' => 'Rulletekstmarkørmønster',
			'settings.creditsPatternDescription' => 'Regulært udtryk til at genkende rulletekstmarkører i kapiteltitler',
			'settings.invalidRegex' => 'Ugyldigt regulært udtryk',
			'settings.regex' => 'Regulært udtryk',
			'settings.downloads' => 'Downloads',
			'settings.downloadLocationDescription' => 'Vælg, hvor downloadet indhold skal gemmes',
			'settings.downloadLocationDefault' => 'Standard (applager)',
			'settings.downloadLocationCustom' => 'Brugerdefineret placering',
			'settings.selectFolder' => 'Vælg mappe',
			'settings.resetToDefault' => 'Nulstil til standard',
			'settings.currentPath' => ({required Object path}) => 'Nuværende: ${path}',
			'settings.downloadLocationChanged' => 'Downloadplacering ændret',
			'settings.downloadLocationReset' => 'Downloadplacering nulstillet',
			'settings.downloadLocationInvalid' => 'Valgt mappe er ikke skrivbar',
			'settings.downloadLocationPickerUnavailable' => 'Mappevalg er ikke tilgængeligt på denne enhed',
			'settings.downloadOnWifiOnly' => 'Download kun via Wi-Fi',
			'settings.downloadOnWifiOnlyDescription' => 'Forhindr downloads via mobildata',
			'settings.autoRemoveWatchedDownloads' => 'Fjern sete downloads automatisk',
			'settings.autoRemoveWatchedDownloadsDescription' => 'Slet sete downloads automatisk',
			'settings.cellularDownloadBlocked' => 'Downloads er blokeret på mobilnettet. Brug Wi-Fi, eller skift indstillingen.',
			'settings.maxVolume' => 'Maksimal lydstyrke',
			'settings.maxVolumeDescription' => 'Tillad lydstyrkeforstærkning over 100 % for stille medier',
			'settings.maxVolumePercent' => ({required Object percent}) => '${percent}%',
			'settings.discordRichPresence' => 'Discord Rich Presence',
			'settings.discordRichPresenceDescription' => 'Vis på Discord, hvad du ser',
			'settings.services' => 'Tjenester',
			'settings.servicesDescription' => 'Forbind Trakt, MyAnimeList, Seerr og mere',
			'settings.manageLibrariesDescription' => 'Omarranger og skjul biblioteker',
			'settings.companionRemoteServer' => 'Fjernbetjeningsserver',
			'settings.companionRemoteServerDescription' => 'Tillad mobilenheder på dit netværk at styre denne app',
			'settings.companionRemoteServerStartFailed' => 'Fjernbetjeningsserveren kunne ikke startes',
			'settings.companionRemoteServerStopFailed' => 'Fjernbetjeningsserveren kunne ikke stoppes',
			'settings.autoPip' => 'Automatisk billede-i-billede',
			'settings.autoPipDescription' => 'Skift automatisk til billede-i-billede, når du forlader appen under afspilning',
			'settings.matchContentFrameRate' => 'Tilpas billedhastigheden til indholdet',
			'settings.matchContentFrameRateDescription' => 'Tilpas skærmens opdateringsfrekvens til videoindhold',
			'settings.matchContentResolution' => 'Tilpas til indholdets opløsning',
			'settings.matchContentResolutionDescription' => 'Skifter skærmen til videoens oprindelige opløsning, så dit tv står for opskaleringen. Menuer og undertekster opskaleres også under afspilning',
			'settings.matchRefreshRate' => 'Tilpas opdateringsfrekvensen',
			'settings.matchRefreshRateDescription' => 'Tilpas skærmens opdateringsfrekvens i fuld skærm',
			'settings.matchDynamicRange' => 'Tilpas dynamikområdet',
			'settings.matchDynamicRangeDescription' => 'Slå HDR til for HDR-indhold og derefter tilbage til SDR',
			'settings.displaySwitchDelay' => 'Forsinkelse ved skærmskift',
			'settings.tunneledPlayback' => 'Tunneleret afspilning',
			'settings.tunneledPlaybackDescription' => 'Brug videotunneling. Slå fra, hvis HDR-afspilning viser sort video, eller bevægelser hakker.',
			'settings.audioPassthrough' => 'Lyd-passthrough',
			'settings.audioPassthroughDescription' => 'Send Dolby/DTS-lyd til din receiver eller dit TV uden genkodning, så surroundlyd bevares. Slå fra, hvis du ikke har lyd.',
			'settings.audioPassthroughDescriptionAppleTv' => 'Brug Apples indbyggede Dolby-dekoder til Dolby Digital Plus, inklusive Atmos. DTS og TrueHD afspilles stadig som flerkanals-PCM. Slå fra, hvis du ikke har lyd.',
			'settings.audioPassthroughOverriddenByNormalization' => 'Fra, mens lydstyrkenormalisering er slået til',
			'settings.downmixCenterBoost' => 'Forstærkning af centerkanal',
			'settings.downmixCenterBoostValue' => ({required Object db}) => '${db} dB',
			'settings.downmixCenterBoostLabel' => 'Forstærkning (dB)',
			'settings.downmixCenterBoostShort' => 'dB',
			'settings.audioDownmixNormalize' => 'Normaliser lydstyrken ved downmix',
			'settings.audioDownmixNormalizeDescription' => 'Sænk mixets lydstyrke for at undgå clipping. Slå fra for at bevare den oprindelige lydstyrke (høje scener kan blive forvrænget).',
			'settings.dvConversionMode' => 'Dolby Vision-konvertering',
			'settings.dvConversionModeDescription' => 'Vælg, hvordan Dolby Vision Profile 7-filer håndteres.',
			'settings.dvConversionAuto' => 'Automatisk',
			'settings.dvConversionNative' => 'Indbygget / deaktiveret',
			'settings.dvConversionDv81' => 'P7 → P8.1',
			'settings.dvConversionHevcStrip' => 'P7 → HEVC',
			'settings.dvConversionAutoDescription' => 'Brug registrering af enhedens funktioner og normal reserveadfærd',
			'settings.dvConversionNativeDescription' => 'Gennemtving indbygget DV7-understøttelse, og undlad at forsøge DV-konvertering igen',
			'settings.dvConversionDv81Description' => 'Tving inline RPU-konvertering til Dolby Vision profil 8.1',
			'settings.dvConversionHevcStripDescription' => 'Fjern Dolby Vision RPU/EL-lag og brug almindelig HEVC',
			'settings.disableDolbyVision' => 'Deaktiver Dolby Vision',
			'settings.disableDolbyVisionDescription' => 'Afspil filens HDR10- eller HLG-lag i stedet for Dolby Vision, når det findes',
			'settings.hdrSdrConversion' => 'HDR til SDR-konvertering',
			'settings.hdrSdrConversionDescription' => 'Vælg, hvad der konverterer HDR-video, når skærmen ikke kan vise HDR.',
			'settings.hdrSdrConversionAuto' => 'Automatisk',
			'settings.hdrSdrConversionAutoDescription' => 'Enhed på Android 9 og nyere, afspiller på ældre versioner',
			'settings.hdrSdrConversionDevice' => 'Enhed',
			'settings.hdrSdrConversionDeviceDescription' => 'Enhedens videohardware konverterer. Hurtigst, men farverne afhænger af enheden',
			'settings.hdrSdrConversionPlayer' => 'Afspiller',
			'settings.hdrSdrConversionPlayerDescription' => 'Afspilleren konverterer. Ensartede farver, men 4K kan hakke på billige tv-bokse',
			'settings.deinterlace' => 'Deinterlacing',
			'settings.deinterlaceDescription' => 'Fjern kamartefakter fra interlaced video (kun mpv-afspiller)',
			'settings.requireProfileSelectionOnOpen' => 'Spørg om profil ved åbning',
			'settings.requireProfileSelectionOnOpenDescription' => 'Vis profilvalg hver gang appen åbnes',
			'settings.forceTvMode' => 'Gennemtving TV-tilstand',
			'settings.forceTvModeDescription' => 'Tving TV-layout. Til enheder, der ikke registreres automatisk. Kræver genstart.',
			'settings.startInFullscreen' => 'Start i fuldskærm',
			'settings.startInFullscreenDescription' => 'Åbn Plezy i fuldskærmstilstand ved opstart',
			'settings.exitFullscreenOnPlayerClose' => 'Forlad fuldskærm ved lukning af afspiller',
			'settings.exitFullscreenOnPlayerCloseDescription' => 'Afslut automatisk fuldskærm, når videoafspilleren lukkes',
			'settings.autoHidePerformanceOverlay' => 'Skjul ydelsesoverlay automatisk',
			'settings.autoHidePerformanceOverlayDescription' => 'Lad ydelsesoverlayet tone ud sammen med afspilningsknapperne',
			'settings.showNavBarLabels' => 'Vis tekst på navigationslinjen',
			'settings.showNavBarLabelsDescription' => 'Vis tekst under ikonerne på navigationslinjen',
			'settings.startupSection' => 'Startsektion',
			'settings.showExploreTab' => 'Vis fanen Opdag',
			'settings.general' => 'Generelt',
			'settings.generalDescription' => 'Sprog, opstart og vinduesadfærd',
			'settings.languageAndRegion' => 'Sprog og region',
			'settings.startup' => 'Opstart',
			'settings.display' => 'Skærm',
			'settings.libraryAndCards' => 'Bibliotek og kort',
			'settings.homeScreen' => 'Startskærm',
			'settings.navigation' => 'Navigation',
			'settings.window' => 'Vindue',
			'settings.liveTv' => 'Live TV',
			'settings.player' => 'Afspiller',
			'settings.videoAndDisplay' => 'Video og skærm',
			'settings.audio' => 'Lyd',
			'settings.quality' => 'Kvalitet',
			'settings.subtitles' => 'Undertekster',
			'settings.seekAndTiming' => 'Søgning og timing',
			'settings.behavior' => 'Adfærd',
			'settings.gestures' => 'Bevægelser',
			'settings.gestureBrightnessSwipe' => 'Lysstyrke-strygning',
			'settings.gestureBrightnessSwipeDescription' => 'Stryg op eller ned i venstre kant for at justere lysstyrken',
			'settings.gestureVolumeSwipe' => 'Lydstyrke-strygning',
			'settings.gestureVolumeSwipeDescription' => 'Stryg op eller ned i højre kant for at justere lydstyrken',
			'settings.gesturePinchToZoom' => 'Klem for at zoome',
			'settings.gesturePinchToZoomDescription' => 'Klem på videoen for at zoome ind eller ud',
			'settings.rememberBrightnessLevel' => 'Husk lysstyrkeniveau',
			'settings.rememberBrightnessLevelDescription' => 'Start afspilning med den lysstyrke, der blev indstillet med den seneste strygning',
			'settings.controls' => 'Kontroller',
			'settings.rememberPlayerChanges' => 'Husk afspillerændringer',
			'settings.rememberPlayerChangesDescription' => 'Hvor en ændring under afspilning gemmes og anvendes igen',
			'settings.scopePlaybackSpeed' => 'Afspilningshastighed',
			'settings.scopeShaderPreset' => 'Shader-forudindstilling',
			'settings.scopeAspectRatio' => 'Billedformat',
			'settings.scopeSyncOffsets' => 'Synkronisering af lyd og undertekster',
			'settings.playerScopeOff' => 'Gem ikke',
			'settings.playerScopeGlobal' => 'Overalt',
			'settings.playerScopeLibrary' => 'Pr. bibliotek',
			'settings.playerScopeTitle' => 'Pr. serie eller film',
			'settings.exportDialogTitle' => 'Eksportér Plezy-indstillinger',
			'search.hint' => 'Søg film, serier, musik...',
			'search.tryDifferentTerm' => 'Prøv en anden søgning',
			'search.searchYourMedia' => 'Søg i dine medier',
			'search.enterTitleActorOrKeyword' => 'Indtast titel, skuespiller eller nøgleord',
			'hotkeys.setShortcutFor' => ({required Object actionName}) => 'Indstil genvej for ${actionName}',
			'hotkeys.clearShortcut' => 'Ryd genvej',
			'hotkeys.noShortcutSet' => 'Ingen genvej angivet',
			'hotkeys.currentShortcut' => 'Nuværende genvej:',
			'hotkeys.pressToRecord' => 'Vælg for at registrere en genvej',
			'hotkeys.recordingShortcut' => 'Tryk på genvejen nu',
			'hotkeys.actions.playPause' => 'Afspil/Pause',
			'hotkeys.actions.volumeUp' => 'Lydstyrke op',
			'hotkeys.actions.volumeDown' => 'Lydstyrke ned',
			'hotkeys.actions.seekForward' => ({required Object seconds}) => 'Spol frem (${seconds}s)',
			'hotkeys.actions.seekBackward' => ({required Object seconds}) => 'Spol tilbage (${seconds}s)',
			'hotkeys.actions.fullscreenToggle' => 'Slå fuldskærm til/fra',
			'hotkeys.actions.muteToggle' => 'Slå lyd til/fra',
			'hotkeys.actions.subtitleToggle' => 'Slå undertekster til/fra',
			'hotkeys.actions.audioTrackNext' => 'Næste lydspor',
			'hotkeys.actions.subtitleTrackNext' => 'Næste undertekstspor',
			'hotkeys.actions.chapterNext' => 'Næste kapitel',
			'hotkeys.actions.chapterPrevious' => 'Forrige kapitel',
			'hotkeys.actions.episodeNext' => 'Næste afsnit',
			'hotkeys.actions.episodePrevious' => 'Forrige afsnit',
			'hotkeys.actions.speedIncrease' => 'Øg hastighed',
			'hotkeys.actions.speedDecrease' => 'Sænk hastighed',
			'hotkeys.actions.speedReset' => 'Nulstil hastighed',
			'hotkeys.actions.zoomIn' => 'Zoom ind',
			'hotkeys.actions.zoomOut' => 'Zoom ud',
			'hotkeys.actions.zoomReset' => 'Nulstil zoom',
			'hotkeys.actions.subSeekNext' => 'Søg til næste undertekst',
			'hotkeys.actions.subSeekPrev' => 'Søg til forrige undertekst',
			'hotkeys.actions.shaderToggle' => 'Slå shadere til/fra',
			'hotkeys.actions.skipMarker' => 'Spring intro/rulletekster over',
			'hotkeys.actions.screenshot' => 'Tag skærmbillede',
			'fileInfo.title' => 'Filinfo',
			'fileInfo.overview' => 'Oversigt',
			'fileInfo.video' => 'Video',
			'fileInfo.audio' => 'Lyd',
			'fileInfo.subtitles' => 'Undertekster',
			'fileInfo.images' => 'Indlejrede billeder',
			'fileInfo.dataStreams' => 'Datastrømme',
			'fileInfo.lyrics' => 'Tekster',
			'fileInfo.file' => 'Fil',
			'fileInfo.attachments' => 'Vedhæftninger',
			'fileInfo.delivery' => 'Levering',
			'fileInfo.versionCounter' => ({required Object index, required Object count}) => 'Version ${index} af ${count}',
			'fileInfo.fileCounter' => ({required Object index, required Object count}) => 'Fil ${index} af ${count}',
			'fileInfo.noStreams' => 'Serveren rapporterede ingen strømme for denne fil.',
			'fileInfo.copyPath' => 'Kopiér sti',
			'fileInfo.pathCopied' => 'Filstien er kopieret',
			'fileInfo.codec' => 'Codec',
			'fileInfo.codecTag' => 'Codec-tag',
			'fileInfo.resolution' => 'Opløsning',
			'fileInfo.codedResolution' => 'Kodet opløsning',
			'fileInfo.bitrate' => 'Bitrate',
			'fileInfo.frameRate' => 'Billedhastighed',
			'fileInfo.rotation' => 'Rotation',
			'fileInfo.comment' => 'Kommentar',
			'fileInfo.audioDescription' => 'Lydbeskrivelse',
			'fileInfo.headerCompression' => 'Headerkomprimering',
			'fileInfo.sidecarFile' => 'Sidecar-fil',
			'fileInfo.transportTimestamp' => 'Transporttidsstempel',
			'fileInfo.displayOffset' => 'Visningsforskydning',
			'fileInfo.previewFailureCode' => 'Preview-fejlkode',
			'fileInfo.previewRetries' => 'Preview-forsøg',
			'fileInfo.aspectRatio' => 'Billedformat',
			'fileInfo.pixelAspectRatio' => 'Pixel-billedformat',
			'fileInfo.profile' => 'Profil',
			'fileInfo.level' => 'Niveau',
			'fileInfo.bitDepth' => 'Bitdybde',
			'fileInfo.pixelFormat' => 'Pixelformat',
			'fileInfo.colorSpace' => 'Farverum',
			'fileInfo.colorRange' => 'Farveområde',
			'fileInfo.colorPrimaries' => 'Farveprimærer',
			'fileInfo.colorTransfer' => 'Farveoverførsel',
			'fileInfo.chromaSubsampling' => 'Chroma-subsampling',
			'fileInfo.chromaLocation' => 'Chroma-placering',
			'fileInfo.scanType' => 'Scanningstype',
			'fileInfo.interlaced' => 'Interlaced',
			'fileInfo.anamorphic' => 'Anamorfisk',
			'fileInfo.referenceFrames' => 'Referenceframes',
			'fileInfo.dynamicRange' => 'Dynamisk område',
			'fileInfo.dolbyVision' => 'Dolby Vision',
			'fileInfo.dolbyVisionLevel' => 'Dolby Vision-niveau',
			'fileInfo.dolbyVisionVersion' => 'Dolby Vision-version',
			'fileInfo.dolbyVisionLayers' => 'Dolby Vision-lag',
			'fileInfo.baseLayerCompatibility' => 'Basislagskompatibilitet',
			'fileInfo.avcBitstream' => 'AVC-bitstrøm',
			'fileInfo.nalLengthSize' => 'NAL-længdestørrelse',
			'fileInfo.scalingMatrix' => 'Brugerdefineret skaleringsmatrix',
			'fileInfo.streamIdentifier' => 'Strømidentifikator',
			'fileInfo.streamIndex' => 'Strømindex',
			'fileInfo.streamId' => 'Strøm-ID',
			'fileInfo.language' => 'Sprog',
			'fileInfo.languageCode' => 'Sprogkode',
			'fileInfo.streamTitle' => 'Sportitel',
			'fileInfo.channels' => 'Kanaler',
			'fileInfo.sampleRate' => 'Samplingshastighed',
			'fileInfo.spatialAudio' => 'Rumlig lyd',
			'fileInfo.textBased' => 'Tekstbaseret',
			'fileInfo.subtitleFormat' => 'Sidecar-format',
			'fileInfo.provider' => 'Udbydder',
			'fileInfo.matchScore' => 'Matchscore',
			'fileInfo.externalDelivery' => 'Kan leveres separat',
			'fileInfo.sidecarPath' => 'Sidecar-sti',
			'fileInfo.sourceStream' => 'Kopieret fra',
			'fileInfo.temporary' => 'Midlertidig',
			'fileInfo.timeBase' => 'Tidsbase',
			'fileInfo.overallBitrate' => 'Samlet bitrate',
			'fileInfo.path' => 'Sti',
			'fileInfo.fileName' => 'Filnavn',
			'fileInfo.size' => 'Størrelse',
			'fileInfo.totalSize' => 'Samlet størrelse',
			'fileInfo.container' => 'Container',
			'fileInfo.duration' => 'Varighed',
			'fileInfo.previewThumbnails' => 'Preview-thumbnails',
			'fileInfo.previewIndex' => 'Preview-index',
			_ => null,
		} ?? switch (path) {
			'fileInfo.packetLength' => 'Pakkelængde',
			'fileInfo.filePresent' => 'Fil til stede',
			'fileInfo.fileReadable' => 'Læsbar af serveren',
			'fileInfo.streamPath' => 'Strømsti',
			'fileInfo.optimizedForStreaming' => 'Optimeret til streaming',
			'fileInfo.has64bitOffsets' => '64-bit-forskydninger',
			'fileInfo.protocol' => 'Protokol',
			'fileInfo.mediaType' => 'Medietype',
			'fileInfo.sourceKind' => 'Kildetype',
			'fileInfo.optimizedVersion' => 'Optimeret version',
			'fileInfo.optimizationTarget' => 'Optimeringsmål',
			'fileInfo.deletedAt' => 'Slettet',
			'fileInfo.remoteSource' => 'Fjernkilde',
			'fileInfo.infiniteStream' => 'Uendelig strøm',
			'fileInfo.directPlay' => 'Direkte afspilning',
			'fileInfo.directStream' => 'Direkte strømning',
			'fileInfo.transcoding' => 'Transkodning',
			'fileInfo.etag' => 'ETag',
			'fileInfo.versionId' => 'Versions-ID',
			'fileInfo.fileId' => 'Fil-ID',
			'fileInfo.defaultAudioTrack' => 'Standard lydspor',
			'fileInfo.defaultSubtitleTrack' => 'Standard undertekstspor',
			'fileInfo.subtitlesOff' => 'Fra',
			'fileInfo.flagDefault' => 'Standard',
			'fileInfo.flagForced' => 'Tvunget',
			'fileInfo.flagSelected' => 'Valgt',
			'fileInfo.flagExternal' => 'Ekstern',
			'fileInfo.flagHearingImpaired' => 'Hørehæmmede',
			'fileInfo.flagDub' => 'Dub',
			'fileInfo.flagOriginal' => 'Original',
			'fileInfo.channelsMono' => 'Mono',
			'fileInfo.dolbyVisionProfile' => ({required Object profile}) => 'Profil ${profile}',
			'mediaMenu.markAsWatched' => 'Markér som set',
			'mediaMenu.markAsUnwatched' => 'Markér som uset',
			'mediaMenu.removeFromContinueWatching' => 'Fjern fra Fortsæt med at se',
			'mediaMenu.viewDetails' => 'Vis detaljer',
			'mediaMenu.goToSeries' => 'Gå til serie',
			'mediaMenu.shufflePlay' => 'Afspil tilfældigt',
			'mediaMenu.shuffleNotAvailableOffline' => 'Tilfældig afspilning er ikke tilgængelig offline',
			'mediaMenu.fileInfo' => 'Filinfo',
			'mediaMenu.rate' => 'Bedøm',
			'mediaMenu.playFromBeginning' => 'Afspil fra begyndelsen',
			'mediaMenu.playVersion' => 'Afspil version...',
			'rateSheet.title' => 'Bedøm',
			'rateSheet.server' => 'Server',
			'rateSheet.favorite' => 'Favorit',
			'rateSheet.favorited' => 'Føjet til favoritter',
			'rateSheet.saved' => 'Gemt',
			'rateSheet.notAvailable' => 'Intet match fundet',
			'rateSheet.noConnectedServices' => 'Forbind en tjeneste under Indstillinger for at bedømme via den.',
			'accessibility.mediaCardMovie' => ({required Object title}) => '${title}, film',
			'accessibility.mediaCardShow' => ({required Object title}) => '${title}, TV-serie',
			'accessibility.mediaCardEpisode' => ({required Object title, required Object episodeInfo}) => '${title}, ${episodeInfo}',
			'accessibility.mediaCardSeason' => ({required Object title, required Object seasonInfo}) => '${title}, ${seasonInfo}',
			'accessibility.mediaCardWatched' => 'set',
			'accessibility.mediaCardPartiallyWatched' => ({required Object percent}) => '${percent} procent set',
			'accessibility.mediaCardUnwatched' => 'uset',
			'accessibility.tapToPlay' => 'Tryk for at afspille',
			'accessibility.decrease' => 'Formindsk',
			'accessibility.increase' => 'Forøg',
			'accessibility.decreaseValue' => ({required Object label}) => 'Formindsk ${label}',
			'accessibility.increaseValue' => ({required Object label}) => 'Forøg ${label}',
			'accessibility.hue' => 'Farvetone',
			'accessibility.saturation' => 'Mætning',
			'accessibility.brightness' => 'Lysstyrke',
			'accessibility.hexColor' => 'Hexfarve',
			'accessibility.expandText' => 'Udvid tekst',
			'accessibility.collapseText' => 'Fold tekst sammen',
			'accessibility.alphabetNavigation' => 'Alfabetnavigation',
			'accessibility.alphabetScrollHint' => 'Stryg op eller ned for at flytte ét bogstav',
			'accessibility.rowColumnPosition' => ({required Object row, required Object rowCount, required Object column, required Object columnCount}) => 'Række ${row} af ${rowCount}, kolonne ${column} af ${columnCount}',
			'accessibility.rowPosition' => ({required Object row, required Object rowCount}) => 'Række ${row} af ${rowCount}',
			'accessibility.autoScrollPlay' => 'Start automatisk rulning',
			'accessibility.autoScrollPause' => 'Sæt automatisk rulning på pause',
			'accessibility.hueShort' => 'H',
			'accessibility.saturationShort' => 'S',
			'accessibility.valueShort' => 'V',
			'tooltips.shufflePlay' => 'Afspil tilfældigt',
			'tooltips.playTrailer' => 'Afspil trailer',
			'tooltips.markAsWatched' => 'Markér som set',
			'tooltips.markAsUnwatched' => 'Markér som uset',
			'audioTracks.track' => ({required Object n}) => 'Lydspor ${n}',
			'videoControls.audioLabel' => 'Lyd',
			'videoControls.subtitlesLabel' => 'Undertekster',
			'videoControls.addTime' => ({required Object amount, required Object unit}) => '+${amount}${unit}',
			'videoControls.letterbox' => 'Letterbox',
			'videoControls.fillScreen' => 'Fyld skærm',
			'videoControls.stretch' => 'Stræk',
			'videoControls.lockRotation' => 'Lås rotation',
			'videoControls.unlockRotation' => 'Lås rotation op',
			'videoControls.timerActive' => 'Timer aktiv',
			'videoControls.playbackWillPauseIn' => ({required Object duration}) => 'Afspilningen sættes på pause om ${duration}',
			'videoControls.sleepTimerEndOfVideo' => 'Slutningen af aktuel video',
			'videoControls.sleepTimerStopAtHeader' => 'Stop ved',
			'videoControls.sleepTimerDurationHeader' => 'Varighed',
			'videoControls.playbackWillPauseAtEnd' => 'Afspilningen sættes på pause ved slutningen af denne video',
			'videoControls.stillWatching' => 'Ser du stadig?',
			'videoControls.pausingIn' => ({required Object seconds}) => 'Sætter på pause om ${seconds} s',
			'videoControls.continueWatching' => 'Fortsæt',
			'videoControls.autoPlayNext' => 'Afspil næste automatisk',
			'videoControls.playNext' => 'Afspil næste',
			'videoControls.playButton' => 'Afspil',
			'videoControls.pauseButton' => 'Pause',
			'videoControls.playbackPaused' => 'Pauseret',
			'videoControls.playbackResumed' => 'Afspiller',
			'videoControls.loadingVideo' => 'Indlæser video',
			'videoControls.showPlaybackControls' => 'Vis afspilningsknapper',
			'videoControls.hidePlaybackControls' => 'Skjul afspilningsknapper',
			'videoControls.seekBackwardButton' => ({required Object seconds}) => 'Spol ${seconds} sekunder tilbage',
			'videoControls.seekForwardButton' => ({required Object seconds}) => 'Spol ${seconds} sekunder frem',
			'videoControls.previousButton' => 'Forrige episode',
			'videoControls.nextButton' => 'Næste episode',
			'videoControls.previousChapterButton' => 'Forrige kapitel',
			'videoControls.nextChapterButton' => 'Næste kapitel',
			'videoControls.muteButton' => 'Slå lyden fra',
			'videoControls.unmuteButton' => 'Slå lyden til',
			'videoControls.settingsButton' => 'Afspilningsindstillinger',
			'videoControls.tracksButton' => 'Lyd og undertekster',
			'videoControls.chaptersButton' => 'Kapitler',
			'videoControls.versionQualityButton' => 'Version og kvalitet',
			'videoControls.versionColumnHeader' => 'Version',
			'videoControls.qualityColumnHeader' => 'Kvalitet',
			'videoControls.qualityOriginal' => 'Original',
			'videoControls.qualityPresetLabel' => ({required Object resolution, required Object bitrate}) => '${resolution}p ${bitrate} Mbps',
			'videoControls.transcodeUnavailableFallback' => 'Transkodning utilgængelig — afspiller original kvalitet',
			'videoControls.subtitleUnavailableFallback' => 'De valgte undertekster kunne ikke indlæses — afspilningen fortsætter uden undertekster',
			'videoControls.pipButton' => 'Billede-i-billede-tilstand',
			'videoControls.aspectRatioButton' => 'Billedformat',
			'videoControls.ambientLighting' => 'Omgivelsesbelysning',
			'videoControls.fullscreenButton' => 'Fuldskærm',
			'videoControls.exitFullscreenButton' => 'Forlad fuldskærm',
			'videoControls.alwaysOnTopButton' => 'Altid øverst',
			'videoControls.rotationLockButton' => 'Rotationslås',
			'videoControls.lockScreen' => 'Lås skærm',
			'videoControls.screenLockButton' => 'Skærmlås',
			'videoControls.longPressToUnlock' => 'Hold nede for at låse op',
			'videoControls.timelineSlider' => 'Videotidslinje',
			'videoControls.volumeSlider' => 'Lydstyrkeniveau',
			'videoControls.endsAt' => ({required Object time}) => 'Slutter kl. ${time}',
			'videoControls.pipActive' => 'Afspiller i billede-i-billede',
			'videoControls.pipFailed' => 'Billede-i-billede kunne ikke starte',
			'videoControls.screenshotSaved' => 'Skærmbillede gemt',
			'videoControls.zoomPercent' => ({required Object percent}) => 'Zoom ${percent}%',
			'videoControls.volumePercent' => ({required Object percent}) => 'Lydstyrke ${percent}%',
			'videoControls.pipErrors.androidVersion' => 'Kræver Android 8.0 eller nyere',
			'videoControls.pipErrors.iosVersion' => 'Kræver iOS 15.0 eller nyere',
			'videoControls.pipErrors.permissionDisabled' => 'Billede-i-billede er deaktiveret. Slå det til i systemindstillinger.',
			'videoControls.pipErrors.notSupported' => 'Enheden understøtter ikke billede-i-billede',
			'videoControls.pipErrors.voSwitchFailed' => 'Kunne ikke skifte videooutput til billede-i-billede',
			'videoControls.pipErrors.failed' => 'Billede-i-billede kunne ikke starte',
			'videoControls.pipErrors.prepareFailed' => 'Billede-i-billede kunne ikke forberedes',
			'videoControls.pipErrors.unknown' => ({required Object error}) => 'Der opstod en fejl: ${error}',
			'videoControls.chapters' => 'Kapitler',
			'videoControls.noChaptersAvailable' => 'Ingen kapitler tilgængelige',
			'videoControls.queue' => 'Kø',
			'videoControls.noQueueItems' => 'Ingen elementer i køen',
			'videoControls.noAudioDevicesAvailable' => 'Ingen lydenheder tilgængelige',
			'videoControls.searchSubtitles' => 'Søg undertekster',
			'videoControls.language' => 'Sprog',
			'videoControls.noSubtitlesFound' => 'Ingen undertekster fundet',
			'videoControls.subtitleDownloaded' => 'Undertekst downloadet',
			'videoControls.subtitleDownloadedNotApplied' => 'Underteksten blev downloadet, men kunne ikke vælges',
			'videoControls.subtitleDownloadFailed' => 'Kunne ikke downloade undertekst',
			'videoControls.searchLanguages' => 'Søg sprog...',
			'videoControls.skipIntro' => 'Spring intro over',
			'videoControls.skipCredits' => 'Spring rulletekster over',
			'videoControls.nextEpisode' => 'Næste episode',
			'videoControls.subtitleTrack' => ({required Object n}) => 'Spor ${n}',
			'videoControls.subtitleFile' => ({required Object name}) => 'Undertekst ${name}',
			'videoControls.forcedTrack' => ({required Object label}) => '${label} (tvunget)',
			'videoControls.osdSubtitlesOff' => 'Undertekster: Fra',
			'videoControls.osdSubtitles' => ({required Object track}) => 'Undertekster: ${track}',
			'videoControls.osdAudio' => ({required Object track}) => 'Lyd: ${track}',
			'messages.markedAsWatched' => 'Markeret som set',
			'messages.markedAsUnwatched' => 'Markeret som uset',
			'messages.markedAsWatchedOffline' => 'Markeret som set (synkroniseres online)',
			'messages.markedAsUnwatchedOffline' => 'Markeret som uset (synkroniseres online)',
			'messages.autoRemovedWatchedDownload' => ({required Object title}) => 'Automatisk fjernet: ${title}',
			'messages.autoRemovedWatchedDownloads' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n, one: 'Fjernede automatisk ${n} set download', other: 'Fjernede automatisk ${n} sete downloads', ), 
			'messages.removedFromContinueWatching' => 'Fjernet fra Fortsæt med at se',
			'messages.errorLoading' => ({required Object error}) => 'Fejl: ${error}',
			'messages.searchPartialResults' => 'Nogle medieservere kunne ikke søges i. Viser tilgængelige resultater.',
			'messages.streamInterrupted' => 'Streamen blev afbrudt. Tryk på afspil, eller spol for at prøve igen.',
			'messages.fileInfoNotAvailable' => 'Filinfo ikke tilgængelig',
			'messages.playbackAuthenticationRequired' => 'Log ind på medieserveren igen for at afspille dette element.',
			'messages.playbackServerUnavailable' => 'Medieserveren er ikke tilgængelig. Prøv igen senere.',
			'messages.playbackDataInvalid' => 'Serveren returnerede ugyldige afspilningsoplysninger.',
			'messages.playbackCancelled' => 'Afspilningen blev annulleret.',
			'messages.playbackFailed' => 'Afspilningen kunne ikke startes.',
			'messages.playbackFailedDetail' => ({required Object error}) => 'Afspilningen kunne ikke startes: ${error}',
			'messages.audioOutputFailed' => 'Lydoutputtet reagerer ikke længere. Tjek lydforbindelsen til tv\'et eller receiveren; hvis andre apps heller ikke har lyd, skal du genstarte enheden.',
			'messages.mediaUnavailable' => 'Dette indhold er ikke længere tilgængeligt.',
			'messages.errorLoadingFileInfo' => ({required Object error}) => 'Fejl ved indlæsning af filinfo: ${error}',
			'messages.errorLoadingSeries' => 'Fejl ved indlæsning af serie',
			'messages.musicNotSupported' => 'Musikafspilning understøttes endnu ikke',
			'messages.noDescriptionAvailable' => 'Ingen beskrivelse tilgængelig',
			'messages.noProfilesAvailable' => 'Ingen profiler tilgængelige',
			'messages.contactAdminForProfiles' => 'Kontakt din serveradministrator for at tilføje profiler',
			'messages.unableToDetermineLibrarySection' => 'Kunne ikke finde bibliotekssektionen for dette element',
			'messages.logsCleared' => 'Logfilerne blev ryddet',
			'messages.logsCopied' => 'Logfilerne blev kopieret til udklipsholderen',
			'messages.noLogsAvailable' => 'Ingen logfiler tilgængelige',
			'messages.logoutConfirm' => 'Er du sikker på, at du vil logge ud?',
			'messages.noSeasonsFound' => 'Ingen sæsoner fundet',
			'messages.seasonsLoadFailed' => 'Kunne ikke indlæse sæsoner',
			'messages.noEpisodesFound' => 'Ingen episoder fundet i første sæson',
			'messages.noEpisodesFoundGeneral' => 'Ingen episoder fundet',
			'messages.episodesLoadFailed' => 'Kunne ikke indlæse episoder',
			'messages.noResultsFound' => 'Ingen resultater fundet',
			'messages.sleepTimerSet' => ({required Object label}) => 'Sove-timer indstillet til ${label}',
			'messages.noItemsAvailable' => 'Ingen elementer tilgængelige',
			'messages.failedToCreatePlayQueueNoItems' => 'Kunne ikke oprette en afspilningskø — ingen elementer',
			'messages.failedPlayback' => ({required Object action, required Object error}) => 'Kunne ikke ${action}: ${error}',
			'messages.switchingToCompatiblePlayer' => 'Skifter til kompatibel afspiller...',
			'messages.serverLimitTitle' => 'Afspilning mislykkedes',
			'messages.serverLimitBody' => 'Serverfejl (HTTP 500). En båndbredde- eller transkodningsgrænse afviste sandsynligvis sessionen. Bed ejeren om at justere den.',
			'messages.mediaUnreadableTitle' => 'Fil utilgængelig',
			'messages.mediaUnreadableBody' => 'Serveren fandt dette emne, men kunne ikke læse filen (HTTP 404). Filen er sandsynligvis flyttet, slettet, eller dens lager er offline. Bed serverejeren om at kontrollere filen og scanne biblioteket igen.',
			'messages.serverBusyTitle' => 'Stream er ikke tilgængelig',
			'messages.serverBusyBody' => 'Serveren blev ved med at afvise at streame denne fil (HTTP 503). Den er muligvis ved at genstarte eller optaget, eller filens lager er muligvis offline. Prøv igen om et øjeblik – hvis det bliver ved med at ske, skal du bede serverejeren om at kontrollere serveren og filens lager.',
			'messages.playbackNotAllowedTitle' => 'Afspilning er ikke tilladt',
			'messages.playbackNotAllowedBody' => 'Serveren afviste at streame dette emne (HTTP 403). Din konto har muligvis ikke tilladelse til at afspille det, eller serveren tillader muligvis kun afspilning på sit lokale netværk.',
			'messages.logsUploaded' => 'Logfilerne blev uploadet',
			'messages.logsUploadFailed' => 'Logfilerne kunne ikke uploades',
			'messages.logId' => 'Log-ID',
			'messages.burnedSubtitlesUseMenu' => 'Underteksterne er indbrændt i denne stream. Skift dem i undertekstmenuen.',
			'messages.noVideoUrl' => 'Ingen video-URL er tilgængelig',
			'messages.playbackDataNotPrepared' => 'Afspilningen blev startet, før dens data var klar',
			'messages.trackSelectionNotRemembered' => 'Dette sporvalg gælder kun for den aktuelle afspilning.',
			'messages.serverUnavailableForProfile' => 'Ingen server er tilgængelig for den aktive profil',
			'subtitlingStyling.text' => 'Tekst',
			'subtitlingStyling.border' => 'Kant',
			'subtitlingStyling.background' => 'Baggrund',
			'subtitlingStyling.fontSize' => 'Skriftstørrelse',
			'subtitlingStyling.textColor' => 'Tekstfarve',
			'subtitlingStyling.borderSize' => 'Kantstørrelse',
			'subtitlingStyling.borderColor' => 'Kantfarve',
			'subtitlingStyling.backgroundOpacity' => 'Baggrundsopacitet',
			'subtitlingStyling.backgroundColor' => 'Baggrundsfarve',
			'subtitlingStyling.position' => 'Position',
			'subtitlingStyling.assOverride' => 'ASS-tilsidesættelse',
			'subtitlingStyling.overrideScale' => 'Skaler',
			'subtitlingStyling.overrideForce' => 'Gennemtving',
			'subtitlingStyling.overrideStrip' => 'Fjern formatering',
			'subtitlingStyling.positionTop' => 'Øverst',
			'subtitlingStyling.positionBottom' => 'Nederst',
			'subtitlingStyling.useMargins' => 'Brug margener',
			'subtitlingStyling.useMarginsDescription' => 'Tillad tekstundertekster i området uden for videoen. Formaterede undertekster kan beholde deres oprindelige placering.',
			'subtitlingStyling.anchorToScreen' => 'Fastgør til skærmen',
			'subtitlingStyling.anchorToScreenDescription' => 'Vis tekstundertekster i de sorte bjælker under video i bredformat',
			'subtitlingStyling.bold' => 'Fed',
			'subtitlingStyling.italic' => 'Kursiv',
			'subtitlingStyling.renderResolution' => 'Gengivelsesopløsning',
			'subtitlingStyling.renderResolutionScreen' => 'Skærmopløsning',
			'subtitlingStyling.renderResolutionVideo' => 'Videoopløsning',
			'mpvConfig.title' => 'mpv.conf',
			'mpvConfig.description' => 'Avancerede videoafspillerindstillinger',
			'mpvConfig.presets' => 'Forudindstillinger',
			'mpvConfig.noPresets' => 'Ingen gemte forudindstillinger',
			'mpvConfig.saveAsPreset' => 'Gem som forudindstilling...',
			'mpvConfig.presetName' => 'Forudindstillingsnavn',
			'mpvConfig.presetNameHint' => 'Indtast et navn for denne forudindstilling',
			'mpvConfig.loadPreset' => 'Indlæs',
			'mpvConfig.deletePreset' => 'Slet',
			'mpvConfig.presetSaved' => 'Forudindstilling gemt',
			'mpvConfig.presetLoaded' => 'Forudindstilling indlæst',
			'mpvConfig.presetDeleted' => 'Forudindstilling slettet',
			'mpvConfig.confirmDeletePreset' => 'Er du sikker på, at du vil slette denne forudindstilling?',
			'mpvConfig.configPlaceholder' => 'gpu-api=vulkan\nhwdec=auto\n# comment',
			'mpvConfig.lineHint' => 'option=value',
			'mpvConfig.addLine' => 'Tilføj linje',
			'mpvConfig.removeLine' => 'Fjern linje',
			'mpvConfig.embeddedVoHint' => 'vo, gpu-context og gpu-api ignoreres på Linux: indlejret video renderes altid via vo=libmpv på videoplanen, og gpu-next (som compute-shaders som ArtCNN kræver) kan ikke køre indlejret.',
			'profiles.switchingProfile' => 'Skifter profil…',
			'profiles.active' => 'Aktiv',
			'profiles.manage' => 'Administrer',
			'profiles.delete' => 'Slet',
			'profiles.signOut' => 'Log ud',
			'profiles.signOutFailed' => 'Kunne ikke logge ud.',
			'profiles.sectionTitle' => 'Profiler',
			'profiles.summaryMultipleWithActive' => ({required Object count, required Object activeName}) => '${count} profiler · aktiv: ${activeName}',
			'profiles.summaryMultiple' => ({required Object count}) => '${count} profiler',
			'profiles.add' => 'Tilføj',
			'profiles.noConnections' => 'Ingen forbindelser',
			'profiles.incorrectPinTryAgain' => 'Forkert PIN. Prøv igen.',
			'connections.sectionTitle' => 'Forbindelser',
			'connections.addConnection' => 'Tilføj forbindelse',
			'connections.sessionExpiredOne' => ({required Object name}) => 'Sessionen er udløbet for ${name}',
			'connections.sessionExpiredMany' => ({required Object count}) => 'Sessionerne er udløbet for ${count} servere',
			'connections.accessDeniedOne' => ({required Object name}) => '${name} nægtede adgang for denne konto',
			'connections.accessDeniedMany' => ({required Object count}) => '${count} servere nægtede adgang for denne konto',
			'connections.signInAgain' => 'Log ind igen',
			'accountPreferences.sectionTitle' => 'Kontopræferencer',
			'accountPreferences.unavailable' => 'Kan ikke nå denne konto',
			'accountPreferences.autoSelectAudio' => 'Vælg lyd ud fra sprog',
			'accountPreferences.subtitleMode' => 'Slå undertekster til',
			'accountPreferences.subtitleModes.none' => 'Manuelt valgt',
			'accountPreferences.subtitleModes.defaultMode' => 'Følg sporets flag',
			'accountPreferences.subtitleModes.always' => 'Altid aktiveret',
			'accountPreferences.subtitleModes.onlyForced' => 'Kun tvungne undertekster',
			'accountPreferences.subtitleModes.smart' => 'Vis ved fremmedsproget lyd',
			'accountPreferences.forcedSubtitleOptions.onlyForced' => 'Kun tvungne undertekster',
			'accountPreferences.watchedIndicatorOptions.none' => 'Aldrig',
			'accountPreferences.watchedIndicatorOptions.movies' => 'Kun film',
			'accountPreferences.watchedIndicatorOptions.shows' => 'Kun TV-serier',
			'discover.title' => 'Opdag',
			'discover.noContentAvailable' => 'Intet indhold tilgængeligt',
			'discover.addMediaToLibraries' => 'Tilføj medier til dine biblioteker',
			'discover.continueWatching' => 'Fortsæt med at se',
			'discover.nextUp' => 'Næste afsnit',
			'discover.playEpisode' => ({required Object season, required Object episode}) => 'S${season}E${episode}',
			'discover.overview' => 'Oversigt',
			'discover.cast' => 'Rollebesætning',
			'discover.extras' => 'Trailere og ekstramateriale',
			'discover.studio' => 'Studie',
			'discover.rating' => 'Bedømmelse',
			'discover.director' => 'Instruktør',
			'discover.directors' => 'Instruktører',
			'discover.movie' => 'Film',
			'discover.tvShow' => 'TV-serie',
			'discover.minutesLeft' => ({required Object minutes}) => '${minutes} min tilbage',
			'discover.moreLikeThis' => 'Mere som dette',
			'discover.titleCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n, one: '${n} titel', other: '${n} titler', ), 
			'errors.searchFailed' => ({required Object error}) => 'Søgning mislykkedes: ${error}',
			'errors.searchUnavailable' => 'Søgningen kunne ikke nå nogen medieserver.',
			'errors.connectionTimeout' => ({required Object context}) => 'Forbindelsen fik timeout under indlæsning af ${context}',
			'errors.connectionFailed' => 'Kan ikke oprette forbindelse til medieserver',
			'errors.unableToLoad' => ({required Object context}) => 'Kunne ikke indlæse ${context}. Prøv igen.',
			'errors.noClientAvailable' => 'Ingen klient tilgængelig',
			'errors.failedToSwitchProfile' => ({required Object displayName}) => 'Kunne ikke skifte til ${displayName}',
			'errors.failedToRate' => 'Kunne ikke opdatere bedømmelsen',
			'errors.reasonTimedOut' => 'forbindelsen fik timeout',
			'errors.reasonUnreachable' => 'medieserveren kunne ikke nås',
			'errors.reasonRefused' => 'medieserveren afviste anmodningen',
			'errors.reasonNotFound' => 'elementet findes ikke længere på medieserveren',
			'errors.reasonServerError' => 'medieserveren rapporterede en fejl',
			'errors.reasonCancelled' => 'anmodningen blev annulleret',
			'errors.reasonUnexpected' => 'der opstod en uventet fejl',
			'libraries.title' => 'Biblioteker',
			'libraries.noLibrariesFound' => 'Ingen biblioteker fundet',
			'libraries.allLibrariesHidden' => 'Alle biblioteker er skjult',
			'libraries.hiddenLibrariesCount' => ({required Object count}) => 'Skjulte biblioteker (${count})',
			'libraries.thisLibraryIsEmpty' => 'Dette bibliotek er tomt',
			'libraries.noItemsMatchFilters' => 'Ingen elementer matcher de aktive filtre',
			'libraries.resetFilters' => 'Nulstil filtre',
			'libraries.all' => 'Alle',
			'libraries.clearAll' => 'Ryd alle',
			'libraries.manageLibraries' => 'Administrer biblioteker',
			'libraries.sort' => 'Sortér',
			'libraries.sortBy' => 'Sortér efter',
			'libraries.filters' => 'Filtre',
			'libraries.showLibrary' => 'Vis bibliotek',
			'libraries.hideLibrary' => 'Skjul bibliotek',
			'libraries.libraryOptions' => 'Biblioteksindstillinger',
			'libraries.content' => 'biblioteksindhold',
			'libraries.selectLibrary' => 'Vælg bibliotek',
			'libraries.filtersWithCount' => ({required Object count}) => 'Filtre (${count})',
			'libraries.noRecommendations' => 'Ingen anbefalinger tilgængelige',
			'libraries.noCollections' => 'Ingen samlinger i dette bibliotek',
			'libraries.noFoldersFound' => 'Ingen mapper fundet',
			'libraries.folders' => 'mapper',
			'libraries.tabs.recommended' => 'Anbefalet',
			'libraries.tabs.browse' => 'Gennemse',
			'libraries.tabs.collections' => 'Samlinger',
			'libraries.tabs.playlists' => 'Playlister',
			'libraries.groupings.title' => 'Gruppering',
			'libraries.groupings.all' => 'Alle',
			'libraries.groupings.movies' => 'Film',
			'libraries.groupings.shows' => 'TV-serier',
			'libraries.groupings.seasons' => 'Sæsoner',
			'libraries.groupings.episodes' => 'Episoder',
			'libraries.groupings.artists' => 'Kunstnere',
			'libraries.groupings.albums' => 'Album',
			'libraries.groupings.tracks' => 'Numre',
			'libraries.groupings.folders' => 'Mapper',
			'libraries.filterCategories.genre' => 'Genre',
			'libraries.filterCategories.year' => 'År',
			'libraries.filterCategories.contentRating' => 'Aldersvurdering',
			'libraries.filterCategories.tag' => 'Tag',
			'libraries.filterCategories.unwatched' => 'Usete',
			'libraries.sortLabels.title' => 'Titel',
			'libraries.sortLabels.dateAdded' => 'Tilføjet dato',
			'libraries.sortLabels.releaseDate' => 'Udgivelsesdato',
			'libraries.sortLabels.rating' => 'Vurdering',
			'libraries.sortLabels.userRating' => 'Brugerbedømmelse',
			'libraries.sortLabels.productionYear' => 'Produktionsår',
			'libraries.sortLabels.runtime' => 'Spilletid',
			'libraries.sortLabels.startDate' => 'Startdato',
			'libraries.sortLabels.studio' => 'Studie',
			'libraries.sortLabels.dateDownloaded' => 'Downloadet dato',
			'libraries.sortLabels.size' => 'Størrelse',
			'libraries.sortLabels.library' => 'Bibliotek',
			'about.title' => 'Om',
			'about.openSourceLicenses' => 'Open source-licenser',
			'about.versionLabel' => ({required Object version}) => 'Version ${version}',
			'about.viewLicensesDescription' => 'Se licenser for tredjepartsbiblioteker',
			'hubDetail.title' => 'Titel',
			'hubDetail.releaseYear' => 'Udgivelsesår',
			'hubDetail.dateAdded' => 'Tilføjelsesdato',
			'hubDetail.rating' => 'Bedømmelse',
			'hubDetail.noItemsFound' => 'Ingen elementer fundet',
			'logs.clearLogs' => 'Ryd logfiler',
			'logs.copyLogs' => 'Kopiér logfiler',
			'logs.uploadLogs' => 'Upload logfiler',
			'startup.failedTitle' => 'Plezy kunne ikke starte',
			'startup.failedBody' => 'Der gik noget galt under opstart. Oplysningerne nedenfor viser, hvad der gik galt.',
			'startup.failedBodyRepairable' => 'Plezy\'s gemte indstillingsfil er beskadiget og skal genopbygges, før Plezy kan starte. Det hjælper ikke at prøve igen — vælg Reparer lager.',
			'startup.phaseLabel' => 'Trin',
			'startup.showDetails' => 'Vis detaljer',
			'startup.hideDetails' => 'Skjul detaljer',
			'startup.copyDetails' => 'Kopiér detaljer',
			'startup.detailsCopied' => 'Detaljer kopieret til udklipsholder',
			'startup.uploadDetails' => 'Upload detaljer',
			'startup.repairStorage' => 'Reparer lager',
			'startup.repairTitle' => 'Reparer gemte data?',
			'startup.repairBodyCommon' => 'Plezy\'s indstillingsfil er beskadiget og kan ikke læses. Reparation nulstiller alle indstillinger til deres standardværdier.',
			'startup.repairBodyOneCredential' => 'Én gemt loginoplysning er beskadiget og kan ikke læses. Reparation fjerner kun den; dine andre indstillinger forbliver urørt.',
			'startup.repairBodySignInsKept' => 'Dine servere og profiler bør forblive logget ind.',
			'startup.repairBodySignInsLost' => 'Nøglen, der beskytter dine gemte loginoplysninger, kan ikke gendannes fra denne fil, så du skal logge ind på alle servere og profiler igen. Intet på din medieserver er påvirket.',
			'startup.repairBodySessionsUncertain' => 'Trackere (MAL, AniList, Simkl, Trakt) og Seerr gemmes separat, og det er uvist, om de overlever. Plezy fortæller dig præcis, hvad det beholdt.',
			'startup.repairConfirm' => 'Reparer',
			'startup.repairSucceeded' => 'Lager repareret',
			'startup.repairNeedsRestart' => 'Lager repareret — genstart påkrævet',
			'startup.restartRequiredBody' => 'Dine data er blevet repareret, men Plezy skal starte på ny, før det kan bruge dem. Luk Plezy, og åbn det igen.',
			'startup.quitPlezy' => 'Afslut Plezy',
			'startup.repairFailed' => 'Reparation mislykkedes',
			'startup.repairKeptSignIns' => 'Dine servere og profiler er stadig logget ind.',
			'startup.repairLostSignIns' => 'Nøglen, der beskytter dine gemte loginoplysninger, kunne ikke gendannes. Du skal logge ind på alle servere og profiler igen.',
			'startup.repairLostSessions' => 'Mindst én tracker- eller Seerr-forbindelse gik tabt og skal genetableres.',
			'startup.backupTitle' => 'En kopi af den beskadigede fil blev gemt',
			'startup.backupWarning' => 'Den indeholder dine loginoplysninger. Upload eller del den ikke.',
			'startup.deleteBackup' => 'Slet kopi',
			'startup.backupDeleted' => 'Kopi slettet.',
			'startup.previousFailureTitle' => 'Plezy kunne ikke starte sidste gang',
			'licenses.relatedPackages' => 'Relaterede pakker',
			'licenses.license' => 'Licens',
			'licenses.licenseNumber' => ({required Object number}) => 'Licens ${number}',
			'licenses.licensesCount' => ({required Object count}) => '${count} licenser',
			'navigation.libraries' => 'Biblioteker',
			'navigation.downloads' => 'Downloads',
			'navigation.liveTv' => 'Live TV',
			'navigation.explore' => 'Udforsk',
			'explore.title' => 'Udforsk',
			'explore.selectSource' => 'Vælg kilde',
			'explore.rows.watchlist' => 'Ønskeliste',
			'explore.rows.recommendedMovies' => 'Anbefalede film',
			'explore.rows.recommendedShows' => 'Anbefalede serier',
			'explore.rows.trendingMovies' => 'Populære film lige nu',
			'explore.rows.trendingShows' => 'Populære serier lige nu',
			'explore.rows.popularMovies' => 'Populære film',
			'explore.rows.popularShows' => 'Populære serier',
			'explore.rows.trendingAnime' => 'Populær anime lige nu',
			'explore.rows.suggestedAnime' => 'Anbefalet anime',
			'explore.rows.airingAnime' => 'Bedste aktuelle anime',
			'explore.rows.popularAnime' => 'Mest populære anime',
			'explore.rows.trending' => 'Populært lige nu',
			'explore.rows.upcomingMovies' => 'Kommende film',
			'explore.rows.upcomingShows' => 'Kommende serier',
			'explore.status.airing' => 'Sendes',
			'explore.status.ended' => 'Afsluttet',
			'explore.status.canceled' => 'Aflyst',
			'explore.status.upcoming' => 'Kommende',
			'explore.episodeCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n, one: '${n} afsnit', other: '${n} afsnit', ), 
			'explore.cast' => 'Rollebesætning',
			'explore.characters' => 'Figurer',
			'explore.addToWatchlist' => 'Føj til ønskeliste',
			'explore.removeFromWatchlist' => 'Fjern fra ønskeliste',
			'explore.addedToWatchlist' => 'Føjet til overvågningslisten',
			'explore.removedFromWatchlist' => 'Fjernet fra overvågningslisten',
			'explore.watchlistUpdateFailed' => 'Kunne ikke opdatere ønskelisten',
			'explore.watchlistNoMatch' => 'Kunne ikke knytte dette element til en overvågningsliste',
			'explore.notInLibrary' => 'Ikke i dit bibliotek',
			'explore.inTheseLibraries' => 'I disse biblioteker',
			'explore.checkingLibrary' => 'Tjekker dit bibliotek...',
			'explore.libraryCheckFailed' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n, one: 'Kunne ikke tjekke ${n} server', other: 'Kunne ikke tjekke ${n} servere', ), 
			'explore.emptyTitle' => 'Der er ikke noget her endnu',
			'explore.emptyMessage' => ({required Object source}) => 'Indholdsrækker fra ${source} vises her, når de har indhold.',
			'explore.searchHint' => ({required Object source}) => 'Søg i ${source}',
			'explore.searchEmpty' => ({required Object query}) => 'Ingen resultater for "${query}"',
			'explore.searchPrompt' => ({required Object source}) => 'Søg efter film og serier på ${source}.',
			'explore.searchFailed' => 'Søgningen mislykkedes. Tjek din forbindelse, og prøv igen.',
			'explore.badge.rankPopular' => ({required Object n}) => '#${n} populær',
			'explore.badge.rankAiring' => ({required Object n}) => '#${n} på luften',
			'explore.badge.rankRated' => ({required Object n}) => '#${n} bedømt',
			'explore.badge.rankTrending' => ({required Object n}) => '#${n} populær lige nu',
			'explore.badge.rankSeasonal' => ({required Object n, required Object season}) => '#${n} i ${season}',
			'explore.badge.watchingNow' => ({required Object n}) => '${n} ser med',
			'explore.badge.available' => 'Tilgængelig',
			'explore.badge.partiallyAvailable' => 'Delvist tilgængelig',
			'explore.badge.availableIn4k' => '4K tilgængelig',
			'explore.badge.requested' => 'Anmodet',
			'explore.badge.pendingApproval' => 'Afventer godkendelse',
			'explore.badge.processing' => 'Behandles',
			'explore.badge.declined' => 'Afvist',
			'explore.badge.requestFailed' => 'Anmodningen mislykkedes',
			'explore.badge.requested4k' => '4K anmodet',
			'explore.badge.seasonsAvailable' => ({required Object available, required Object total}) => '${available}/${total} sæsoner',
			'explore.badge.nextEpisodeIn' => ({required Object episode, required Object duration}) => 'Afsnit ${episode} om ${duration}',
			'explore.badge.nextAiringIn' => ({required Object duration}) => 'Næste om ${duration}',
			'explore.badge.episodesShort' => ({required Object n}) => '${n} afsnit',
			'explore.badge.minutesPerEpisode' => ({required Object n}) => '${n} min/afsnit',
			'explore.badge.adult' => '18+',
			'explore.stats.listed' => ({required Object n}) => '${n} opført',
			'explore.stats.viewersDay' => ({required Object n}) => '${n} så det i dag',
			'explore.stats.viewersWeek' => ({required Object n}) => '${n} så det denne uge',
			'explore.stats.viewersMonth' => ({required Object n}) => '${n} så det denne måned',
			'explore.stats.viewersYear' => ({required Object n}) => '${n} så det i år',
			'explore.stats.viewersAllTime' => ({required Object n}) => '${n} seere',
			'explore.stats.planning' => ({required Object n}) => '${n} planlægger at se det',
			'explore.stats.favorited' => ({required Object n}) => '${n} favoritter',
			'explore.stats.dropRate' => ({required Object percent}) => '${percent} droppede det',
			'explore.stats.comments' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n, one: '${n} kommentar', other: '${n} kommentarer', ), 
			_ => null,
		} ?? switch (path) {
			'explore.stats.votes' => ({required Object n}) => '${n} stemmer',
			'explore.stats.watching' => ({required Object n}) => '${n} ser det',
			'explore.stats.completed' => ({required Object n}) => '${n} færdigset',
			'explore.stats.onHold' => ({required Object n}) => '${n} på pause',
			'explore.stats.dropped' => ({required Object n}) => '${n} droppede',
			'explore.season.winter' => 'Vinter',
			'explore.season.spring' => 'Forår',
			'explore.season.summer' => 'Sommer',
			'explore.season.fall' => 'Efterår',
			'explore.season.withYear' => ({required Object season, required Object year}) => '${season} ${year}',
			'explore.format.tv' => 'TV',
			'explore.format.tvShort' => 'TV-kort',
			'explore.format.movie' => 'Film',
			'explore.format.special' => 'Special',
			'explore.format.ova' => 'OVA',
			'explore.format.ona' => 'ONA',
			'explore.format.music' => 'Musik',
			'explore.format.other' => 'Andet',
			'explore.sourceMaterial.original' => 'Original',
			'explore.sourceMaterial.manga' => 'Manga',
			'explore.sourceMaterial.lightNovel' => 'Light novel',
			'explore.sourceMaterial.novel' => 'Roman',
			'explore.sourceMaterial.visualNovel' => 'Visual novel',
			'explore.sourceMaterial.game' => 'Spil',
			'explore.sourceMaterial.webComic' => 'Webtegneserie',
			'explore.sourceMaterial.musicRelease' => 'Musik',
			'explore.sourceMaterial.otherMedia' => 'Andet',
			'explore.creditRole.director' => 'Instruktør',
			'explore.creditRole.writer' => 'Forfatter',
			'explore.creditRole.producer' => 'Producer',
			'explore.creditRole.creator' => 'Skaber',
			'explore.creditRole.composer' => 'Komponist',
			'explore.relation.prequel' => 'Prequel',
			'explore.relation.sequel' => 'Sequel',
			'explore.relation.sideStory' => 'Bihistorie',
			'explore.relation.spinOff' => 'Spin-off',
			'explore.relation.alternativeVersion' => 'Alternativ version',
			'explore.relation.summary' => 'Resumé',
			'explore.relation.parentStory' => 'Hovedhistorie',
			'explore.relation.adaptation' => 'Adaption',
			'explore.relation.other' => 'Relateret',
			'explore.broadcast' => ({required Object day, required Object time}) => 'Sendes ${day} kl. ${time}',
			'explore.broadcastWithZone' => ({required Object day, required Object time, required Object timezone}) => 'Sendes ${day} kl. ${time} ${timezone}',
			'explore.detail.originalTitle' => 'Originaltitel',
			'explore.detail.alsoKnownAs' => 'Også kendt som',
			'explore.detail.studios' => 'Studier',
			'explore.detail.country' => 'Land',
			'explore.detail.language' => 'Sprog',
			'explore.detail.released' => 'Udgivet',
			'explore.detail.physicalRelease' => 'På disk',
			'explore.detail.ended' => 'Afsluttet',
			'explore.detail.addedOn' => ({required Object date}) => 'Tilføjet ${date}',
			'explore.detail.yourRating' => 'Din bedømmelse',
			'explore.detail.budget' => 'Budget',
			'explore.detail.revenue' => 'Billetindtægter',
			'explore.detail.contentAdvisory' => 'Aldersvejledning',
			'explore.detail.tags' => 'Tags',
			'explore.detail.revealSpoilerTags' => 'Vis spoilertags',
			'explore.detail.links' => 'Links',
			'explore.detail.watchOn' => 'Se på',
			'explore.detail.watchTrailer' => 'Se trailer',
			'explore.detail.openOn' => ({required Object site}) => 'Åbn på ${site}',
			'explore.detail.crew' => 'Crew',
			'explore.detail.ratings' => 'Bedømmelser',
			'explore.detail.schedule' => 'Program',
			'explore.detail.recommendedByUsers' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n, one: 'Anbefalet af ${n} bruger', other: 'Anbefalet af ${n} brugere', ), 
			'explore.detail.recommendedBy' => ({required Object who}) => 'Anbefalet af ${who}',
			'explore.detail.favoritedBy' => ({required Object who}) => 'Favorit hos ${who}',
			'explore.detail.unairedEpisodes' => ({required Object n}) => '${n} ikke sendt endnu',
			'explore.detail.recommendedByPercent' => ({required Object percent}) => 'Anbefalet af ${percent} af seerne',
			'explore.detail.relatedTitles' => 'Relaterede titler',
			'explore.detail.background' => 'Baggrund',
			'explore.totalResults' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n, one: '${n} resultat', other: '${n} resultater', ), 
			'liveTv.title' => 'Live TV',
			'liveTv.serverUnavailable' => 'Live-tv-serveren er ikke tilgængelig.',
			'liveTv.live' => 'LIVE',
			'liveTv.searchHint' => 'Søg efter kanaler og programmer',
			'liveTv.now' => 'Nu',
			'liveTv.today' => 'I dag',
			'liveTv.tomorrow' => 'I morgen',
			'liveTv.joinSession' => 'Deltag i igangværende session',
			'liveTv.record' => 'Optag',
			'liveTv.invalidPlaybackData' => ({required Object product}) => '${product} returnerede ugyldige afspilningsdata for Live TV',
			'collections.title' => 'Samlinger',
			'collections.collection' => 'Samling',
			'collections.empty' => 'Samlingen er tom',
			'collections.deleteCollection' => 'Slet samling',
			'collections.deleteConfirm' => ({required Object title}) => 'Slet "${title}"? Dette kan ikke fortrydes.',
			'collections.deleted' => 'Samling slettet',
			'collections.deleteFailed' => 'Kunne ikke slette samling',
			'collections.deleteFailedWithError' => ({required Object error}) => 'Kunne ikke slette samling: ${error}',
			'collections.selectCollection' => 'Vælg samling',
			'collections.collectionName' => 'Samlingsnavn',
			'collections.enterCollectionName' => 'Indtast samlingsnavn',
			'collections.addedToCollection' => 'Tilføjet til samling',
			'collections.errorAddingToCollection' => 'Kunne ikke tilføje til samling',
			'collections.created' => 'Samling oprettet',
			'collections.removeFromCollection' => 'Fjern fra samling',
			'collections.removeFromCollectionConfirm' => ({required Object title}) => 'Fjern "${title}" fra denne samling?',
			'collections.removedFromCollection' => 'Fjernet fra samling',
			'collections.removeFromCollectionFailed' => 'Kunne ikke fjerne fra samling',
			'collections.removeFromCollectionError' => ({required Object error}) => 'Fejl ved fjernelse fra samling: ${error}',
			'collections.searchCollections' => 'Søg i samlinger...',
			'playlists.title' => 'Playlister',
			'playlists.playlist' => 'Playliste',
			'playlists.noPlaylists' => 'Ingen playlister fundet',
			'playlists.create' => 'Opret playliste',
			'playlists.playlistName' => 'Playlistenavn',
			'playlists.enterPlaylistName' => 'Indtast playlistenavn',
			'playlists.delete' => 'Slet playliste',
			'playlists.removeItem' => 'Fjern fra playliste',
			'playlists.smartPlaylist' => 'Smart playliste',
			'playlists.itemCount' => ({required Object count}) => '${count} elementer',
			'playlists.oneItem' => '1 element',
			'playlists.emptyPlaylist' => 'Denne playliste er tom',
			'playlists.deleteConfirm' => 'Slet playliste?',
			'playlists.deleteMessage' => ({required Object name}) => 'Er du sikker på, at du vil slette "${name}"?',
			'playlists.created' => 'Playliste oprettet',
			'playlists.deleted' => 'Playliste slettet',
			'playlists.itemAdded' => 'Tilføjet til playliste',
			'playlists.itemRemoved' => 'Fjernet fra playliste',
			'playlists.selectPlaylist' => 'Vælg playliste',
			'playlists.searchPlaylists' => 'Søg i playlister...',
			'playlists.errorCreating' => 'Kunne ikke oprette playliste',
			'playlists.errorDeleting' => 'Kunne ikke slette playliste',
			'playlists.errorLoading' => 'Kunne ikke indlæse playlister',
			'playlists.errorAdding' => 'Kunne ikke tilføje til playliste',
			'playlists.errorReordering' => 'Kunne ikke ændre rækkefølge på playlisteelement',
			'playlists.errorRemoving' => 'Kunne ikke fjerne fra playliste',
			'music.goToAlbum' => 'Gå til album',
			'music.goToArtist' => 'Gå til kunstner',
			'music.instantMix' => 'Direkte miks',
			'music.playNext' => 'Afspil næste',
			'music.addToQueue' => 'Føj til kø',
			'music.discNumber' => ({required Object n}) => 'Disk ${n}',
			'music.trackCount' => ({required num n}) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('da'))(n, one: '${n} nummer', other: '${n} numre', ), 
			'music.nowPlaying' => 'Afspiller nu',
			'music.playingFrom' => ({required Object title}) => 'Afspiller fra ${title}',
			'music.queue' => 'Kø',
			'music.clearQueue' => 'Ryd kø',
			'music.lyrics' => 'Sangtekst',
			'music.noLyrics' => 'Ingen sangtekst tilgængelig',
			'music.sleepTimer' => 'Sovetimer',
			'music.sleepTimerEndOfTrack' => 'Slutningen af nummeret',
			'music.sleepTimerMinutes' => ({required Object n}) => '${n} minutter',
			'music.stopPlayback' => 'Stop afspilning',
			'music.previousTrack' => 'Forrige nummer',
			'music.nextTrack' => 'Næste nummer',
			'music.repeat' => 'Gentag',
			'music.repeatAll' => 'Gentag alle',
			'music.repeatOne' => 'Gentag ét nummer',
			'music.instantMixNoServer' => 'Ingen server er tilgængelig til et øjeblikkeligt mix',
			'music.instantMixFailed' => 'Kunne ikke indlæse det direkte miks',
			'music.instantMixEmpty' => 'Det direkte miks indeholdt ingen numre',
			'music.noAudioUrl' => ({required Object track}) => 'Ingen lyd-URL er tilgængelig for ${track}',
			'music.discography.singlesAndEps' => 'Singler og EP\'er',
			'music.discography.live' => 'Live',
			'music.discography.compilations' => 'Opsamlinger',
			'watchTogether.title' => 'Se sammen',
			'watchTogether.description' => 'Se indhold synkroniseret med venner og familie',
			'watchTogether.createSession' => 'Opret session',
			'watchTogether.creating' => 'Opretter...',
			'watchTogether.joinSession' => 'Deltag i session',
			'watchTogether.joining' => 'Deltager...',
			'watchTogether.controlMode' => 'Kontroltilstand',
			'watchTogether.controlModeQuestion' => 'Hvem kan styre afspilning?',
			'watchTogether.hostOnly' => 'Kun vært',
			'watchTogether.anyone' => 'Alle',
			'watchTogether.hostingSession' => 'Er vært for sessionen',
			'watchTogether.inSession' => 'Deltager i en session',
			'watchTogether.sessionCode' => 'Sessionskode',
			'watchTogether.openSessionControls' => 'Åbn sessionsstyring for Se sammen',
			'watchTogether.copySessionCode' => 'Kopiér sessionskode',
			'watchTogether.hostControlsPlayback' => 'Værten styrer afspilningen',
			'watchTogether.anyoneCanControl' => 'Alle kan styre afspilningen',
			'watchTogether.hostControls' => 'Værten styrer',
			'watchTogether.anyoneControls' => 'Alle styrer',
			'watchTogether.participants' => 'Deltagere',
			'watchTogether.host' => 'Vært',
			'watchTogether.hostBadge' => 'VÆRT',
			'watchTogether.youAreHost' => 'Du er vært',
			'watchTogether.makeHost' => 'Gør til vært',
			'watchTogether.makeHostQuestion' => 'Overfør vært?',
			'watchTogether.makeHostConfirm' => ({required Object name}) => '${name} styrer afspilningen og sessionen for alle.',
			'watchTogether.transfer' => 'Overfør',
			'watchTogether.hostChangedTo' => ({required Object name}) => '${name} er nu vært',
			'watchTogether.youAreNowHost' => 'Du er nu værten',
			'watchTogether.hostTransferFailed' => ({required Object name}) => 'Kunne ikke gøre ${name} til vært',
			'watchTogether.watchingWithOthers' => 'Ser med andre',
			'watchTogether.endSession' => 'Afslut session',
			'watchTogether.leaveSession' => 'Forlad session',
			'watchTogether.endSessionQuestion' => 'Afslut session?',
			'watchTogether.leaveSessionQuestion' => 'Forlad session?',
			'watchTogether.endSessionConfirm' => 'Dette afslutter sessionen for alle deltagere.',
			'watchTogether.leaveSessionConfirm' => 'Du vil blive fjernet fra sessionen.',
			'watchTogether.endSessionConfirmOverlay' => 'Dette afslutter fællesafspilningen for alle deltagere.',
			'watchTogether.leaveSessionConfirmOverlay' => 'Din forbindelse til fællesafspilningen afbrydes.',
			'watchTogether.end' => 'Afslut',
			'watchTogether.leave' => 'Forlad',
			'watchTogether.syncing' => 'Synkroniserer...',
			'watchTogether.joinWatchSession' => 'Deltag i fællesafspilning',
			'watchTogether.enterCodeHint' => 'Indtast 5-tegns kode',
			'watchTogether.pasteFromClipboard' => 'Indsæt fra udklipsholder',
			'watchTogether.pleaseEnterCode' => 'Indtast en sessionskode',
			'watchTogether.codeMustBe5Chars' => 'Sessionskode skal være 5 tegn',
			'watchTogether.joinInstructions' => 'Indtast værtens sessionskode for at deltage.',
			'watchTogether.failedToCreate' => 'Kunne ikke oprette session',
			'watchTogether.failedToJoin' => 'Kunne ikke deltage i session',
			'watchTogether.sessionCodeCopied' => 'Sessionskode kopieret til udklipsholder',
			'watchTogether.relayUnreachable' => 'Relayserveren kan ikke nås. Blokering hos internetudbyderen kan forhindre Se sammen.',
			'watchTogether.reconnectingToHost' => 'Genopretter forbindelse til vært...',
			'watchTogether.currentPlayback' => 'Nuværende afspilning',
			'watchTogether.joinCurrentPlayback' => 'Deltag i nuværende afspilning',
			'watchTogether.joinCurrentPlaybackDescription' => 'Hop tilbage til det værten ser nu',
			'watchTogether.failedToOpenCurrentPlayback' => 'Kunne ikke åbne nuværende afspilning',
			'watchTogether.participantJoined' => ({required Object name}) => '${name} deltog',
			'watchTogether.participantLeft' => ({required Object name}) => '${name} forlod',
			'watchTogether.participantPaused' => ({required Object name}) => '${name} satte på pause',
			'watchTogether.participantResumed' => ({required Object name}) => '${name} genoptog',
			'watchTogether.participantSeeked' => ({required Object name}) => '${name} ændrede afspilningspositionen',
			'watchTogether.participantChangedSpeed' => ({required Object name, required Object speed}) => '${name} satte hastigheden til ${speed}',
			'watchTogether.participantBuffering' => ({required Object name}) => '${name} bufferer',
			'watchTogether.participantNeedsUpdate' => ({required Object name}) => '${name} bruger en ældre appversion — synkronisering er ikke tilgængelig',
			'watchTogether.resumingWithout' => ({required Object name}) => 'Fortsætter uden ${name}',
			'watchTogether.waitingForParticipants' => 'Venter på, at de andre bliver klar...',
			'watchTogether.waitingForName' => ({required Object name}) => 'Venter på ${name}...',
			'watchTogether.recentRooms' => 'Seneste rum',
			'watchTogether.renameRoom' => 'Omdøb rum',
			'watchTogether.removeRoom' => 'Fjern',
			'watchTogether.guestSwitchUnavailable' => 'Kunne ikke skifte — server ikke tilgængelig for synkronisering',
			'watchTogether.guestSwitchFailed' => 'Kunne ikke skifte — indhold blev ikke fundet på denne server',
			'watchTogether.defaultDisplayName' => 'Bruger',
			'watchTogether.errors.timedOut' => 'Relayserveren svarede ikke i tide',
			'watchTogether.errors.connectionLost' => 'Forbindelsen blev lukket, før sessionen var klar',
			'watchTogether.errors.invalidRelayResponse' => 'Relayserveren sendte et uventet svar',
			'watchTogether.errors.sessionEnded' => 'Værten afsluttede sessionen',
			'watchTogether.errors.sessionUnavailable' => 'Kan ikke genoptage denne session. Deltag i eller opret et rum for at fortsætte.',
			'downloads.title' => 'Downloads',
			'downloads.manage' => 'Administrer',
			'downloads.tvShows' => 'TV-serier',
			'downloads.movies' => 'Film',
			'downloads.music' => 'Musik',
			'downloads.tracksQueued' => ({required Object count}) => '${count} numre i kø til download',
			'downloads.noDownloads' => 'Ingen downloads endnu',
			'downloads.noDownloadsDescription' => 'Downloadet indhold vises her til offlinevisning',
			'downloads.downloadNow' => 'Download',
			'downloads.deleteDownload' => 'Slet download',
			'downloads.retryDownload' => 'Prøv download igen',
			'downloads.downloadQueued' => 'Download i kø',
			'downloads.downloadResumed' => 'Download genoptaget',
			'downloads.serverErrorBitrate' => 'Serverfejl: filen overskrider muligvis grænsen for ekstern bitrate',
			'downloads.storageFull' => 'Downloads blev stoppet for at beskytte den ledige lagerplads. Frigør plads, eller vælg en anden downloadplacering, og prøv igen.',
			'downloads.storageUnavailable' => 'Downloads blev stoppet, fordi den tilgængelige lagerplads ikke kunne kontrolleres. Tjek downloadplaceringen, og prøv igen.',
			'downloads.episodesQueued' => ({required Object count}) => '${count} episoder i downloadkø',
			'downloads.downloadDeleted' => 'Download slettet',
			'downloads.deleteConfirm' => ({required Object title}) => 'Slet "${title}" fra denne enhed?',
			'downloads.cancelledDownloadTitle' => 'Annulleret download',
			'downloads.cancelledDownloadMessage' => 'Denne download blev annulleret. Hvad vil du gøre?',
			'downloads.allEpisodesAlreadyDownloaded' => 'Alle episoder er allerede downloadet',
			'downloads.resumeDownload' => 'Genoptag download',
			'downloads.cancelledDownload' => 'Annulleret download',
			'downloads.syncingFile' => ({required Object file, required Object status}) => '${file} (synkroniserer ${status})',
			'downloads.downloadedFileClickToComplete' => ({required Object file}) => '${file} downloadet — klik for at fuldføre',
			'downloads.partialDownloadClickToComplete' => 'Delvist downloadet — klik for at fuldføre',
			'downloads.deleting' => 'Sletter...',
			'downloads.deletingWithProgress' => ({required Object title, required Object current, required Object total}) => 'Sletter ${title}... (${current} af ${total})',
			'downloads.queuedTooltip' => 'I kø',
			'downloads.queuedFilesTooltip' => ({required Object files}) => 'I kø: ${files}',
			'downloads.downloadingTooltip' => 'Downloader...',
			'downloads.downloadingFilesTooltip' => ({required Object files}) => 'Downloader ${files}',
			'downloads.noDownloadsTree' => 'Ingen downloads',
			'downloads.pauseAll' => 'Sæt alle på pause',
			'downloads.resumeAll' => 'Genoptag alle',
			'downloads.deleteAll' => 'Slet alle',
			'downloads.selectVersion' => 'Vælg version',
			'downloads.allEpisodes' => 'Alle episoder',
			'downloads.unwatchedOnly' => 'Kun usete',
			'downloads.nextNUnwatched' => ({required Object count}) => 'Næste ${count} usete',
			'downloads.customAmount' => 'Angiv antal...',
			'downloads.includeSpecials' => 'Medtag specialafsnit',
			'downloads.howManyEpisodes' => 'Hvor mange episoder?',
			'downloads.invalidEpisodeCount' => 'Indtast et gyldigt antal episoder.',
			'downloads.keepSynced' => 'Synkroniser løbende',
			'downloads.downloadOnce' => 'Download én gang',
			'downloads.keepNUnwatched' => ({required Object count}) => 'Behold ${count} usete',
			'downloads.editSyncRule' => 'Rediger synkroniseringsregel',
			'downloads.removeSyncRule' => 'Fjern synkroniseringsregel',
			'downloads.removeSyncRuleConfirm' => ({required Object title}) => 'Stop synkronisering af "${title}"? Downloadede episoder beholdes.',
			'downloads.removeListSyncRuleConfirm' => ({required Object title}) => 'Stop synkronisering af "${title}"?',
			'downloads.deleteSyncRuleDownloads' => 'Slet også tilknyttede downloads',
			'downloads.deleteSyncRuleDownloadsDescription' => 'Downloads, der bruges af en anden synkroniseringsregel eller profil, beholdes.',
			'downloads.syncRuleCreated' => ({required Object count}) => 'Synkroniseringsregel oprettet — beholder ${count} usete episoder',
			'downloads.syncRuleUpdated' => 'Synkroniseringsregel opdateret',
			'downloads.syncRuleRemoved' => 'Synkroniseringsregel fjernet',
			'downloads.syncRuleAndDownloadsRemoved' => 'Synkroniseringsregel og tilknyttede downloads fjernet',
			'downloads.syncRuleCleanupBusy' => 'Synkroniseringsregler opdateres lige nu. Prøv igen om et øjeblik.',
			'downloads.syncRuleCleanupUnavailable' => 'Tilknyttede downloads kunne ikke identificeres sikkert. Genopret forbindelse til serveren og prøv igen, eller fjern reglen uden at slette downloads.',
			'downloads.syncedNewEpisodes' => ({required Object count, required Object title}) => 'Synkroniserede ${count} nye episoder for ${title}',
			'downloads.activeSyncRules' => 'Synkroniseringsregler',
			'downloads.noSyncRules' => 'Ingen synkroniseringsregler',
			'downloads.manageSyncRule' => 'Administrer synkronisering',
			'downloads.editEpisodeCount' => 'Antal episoder',
			'downloads.editSyncFilter' => 'Synkroniseringsfilter',
			'downloads.syncAllItems' => 'Synkroniserer alle elementer',
			'downloads.syncUnwatchedItems' => 'Synkroniserer usete elementer',
			'downloads.syncRuleServerContext' => ({required Object server, required Object status}) => 'Server: ${server} • ${status}',
			'downloads.syncRuleAvailable' => 'Tilgængelig',
			'downloads.syncRuleOffline' => 'Offline',
			'downloads.syncRuleSignInRequired' => 'Login påkrævet',
			'downloads.syncRuleAccessDenied' => 'Adgang nægtet',
			'downloads.syncRuleNotAvailableForProfile' => 'Ikke tilgængelig for nuværende profil',
			'downloads.syncRuleUnknownServer' => 'Ukendt server',
			'downloads.syncRuleListCreated' => 'Synkroniseringsregel oprettet',
			'downloads.backgroundWarning.bannerBlocked' => 'Downloads stopper, når du forlader appen',
			'downloads.backgroundWarning.bannerDegraded' => 'Downloads i baggrunden kan være begrænsede',
			'downloads.backgroundWarning.bannerAction' => 'Detaljer',
			'downloads.backgroundWarning.sheetTitle' => 'Downloads i baggrunden er blokeret',
			'downloads.backgroundWarning.sheetTitleDegraded' => 'Downloads i baggrunden kan være begrænsede',
			'downloads.backgroundWarning.sheetIntro' => 'Android forhindrer Plezy i at downloade stabilt i baggrunden.',
			'downloads.backgroundWarning.sheetIntroDegraded' => 'Din enhed begrænser, hvornår Plezy kan downloade i baggrunden.',
			'downloads.backgroundWarning.reasonBackgroundRestricted' => 'Plezys baggrundsaktivitet er begrænset. Indstil batteriforbruget eller baggrundsaktiviteten til "Ubegrænset".',
			'downloads.backgroundWarning.reasonStandbyRestricted' => 'Android har sat Plezy i begrænset standbytilstand. Indstil batteriforbruget til "Ubegrænset".',
			'downloads.backgroundWarning.reasonDownloadChannelBlocked' => 'Notifikationer om downloads er slået fra, så status og betjeningsknapper muligvis ikke er tilgængelige.',
			'downloads.backgroundWarning.reasonNotificationsDisabled' => 'Notifikationer er slået fra. På Android 13 eller nyere er de nødvendige ved lange downloads i baggrunden.',
			'downloads.backgroundWarning.reasonDataSaver' => 'Datasparefunktionen er slået til, hvilket blokerer downloads i baggrunden via mobildata. Downloads bør stadig køre på Wi-Fi.',
			'downloads.backgroundWarning.reasonOemUnknown' => 'Downloads stoppede gentagne gange, mens Plezy var i baggrunden. Tjek Plezys indstillinger for batteriforbrug eller baggrundsaktivitet.',
			'downloads.backgroundWarning.openSettings' => 'Åbn indstillinger',
			'downloads.backgroundWarning.stillNotWorking' => 'Enhedsspecifik hjælp',
			'downloads.backgroundWarning.stillNotWorkingDescription' => 'Se vejledningen til din enhed, eller send en logfil fra Indstillinger › Vis logfiler, hvis problemet fortsætter.',
			'downloads.backgroundWarning.dialogTitle' => 'Downloads bliver muligvis ikke færdige',
			'downloads.backgroundWarning.dialogDownloadAnyway' => 'Download alligevel',
			'downloads.backgroundWarning.dialogFixFirst' => 'Løs dette først',
			'downloads.backgroundWarning.statusTile' => 'Downloads i baggrunden',
			'downloads.backgroundWarning.statusOk' => 'Må køre i baggrunden',
			'downloads.backgroundWarning.statusBlocked' => 'Blokeret af systemindstillinger',
			'downloads.backgroundWarning.statusDegraded' => 'Begrænset af systemindstillinger',
			'downloads.backgroundWarning.statusUnknown' => 'Endnu ikke kontrolleret',
			'downloads.backgroundWarning.settingsUnavailable' => 'Kunne ikke åbne systemindstillingerne på denne enhed',
			'downloads.backgroundWarning.linkUnavailable' => 'Kunne ikke åbne dontkillmyapp.com på denne enhed',
			'downloads.options' => 'Valgmuligheder for downloads',
			'downloads.groupings.library' => 'Bibliotek',
			'downloads.unknownLibrary' => 'Ukendt bibliotek',
			'downloads.unknownShow' => 'Ukendt serie',
			'downloads.unknownSeason' => 'Ukendt sæson',
			'downloads.unknownAlbum' => 'Ukendt album',
			'downloads.completedOfTotal' => ({required Object completed, required Object total}) => '${completed}/${total} fuldført',
			'downloads.errorFileNotFound' => 'Filen blev ikke fundet (404)',
			'downloads.errorDownloadNotAllowed' => 'Serveren tillader ikke download (403)',
			'downloads.errorDownloadFailed' => 'Download mislykkedes',
			'downloads.errorDownloadFailedWithReason' => ({required Object reason}) => 'Download mislykkedes: ${reason}',
			'downloads.errorHttpStatus' => ({required Object status}) => 'Download mislykkedes (HTTP ${status})',
			'downloads.errorPostProcessing' => ({required Object reason}) => 'Efterbehandling mislykkedes: ${reason}',
			'downloads.reasonFileNotSaved' => 'filen kunne ikke gemmes på denne enhed',
			'downloads.reasonCannotResume' => 'den delvise download kunne ikke genoptages',
			'downloads.reasonDeviceStorageFull' => 'der er ikke mere lagerplads på denne enhed',
			'downloads.notificationDownloading' => 'Downloader...',
			'downloads.notificationComplete' => 'Download fuldført',
			'downloads.notificationPaused' => 'Download sat på pause',
			'shaders.title' => 'Shadere',
			'shaders.noShaderDescription' => 'Ingen videoforbedring',
			'shaders.nvscalerDescription' => 'NVIDIA-billedskalering for skarpere video',
			'shaders.artcnnVariantNeutral' => 'Neutral',
			'shaders.artcnnVariantDenoise' => 'Støjreduktion',
			'shaders.artcnnVariantDenoiseSharpen' => 'Støjreduktion + skarphed',
			'shaders.qualityFast' => 'Hurtig',
			'shaders.qualityHQ' => 'Høj kvalitet',
			'shaders.mode' => 'Tilstand',
			'shaders.importShader' => 'Importér shader',
			'shaders.customShaderDescription' => 'Brugerdefineret GLSL-shader',
			'shaders.shaderImported' => 'Shader importeret',
			'shaders.shaderImportFailed' => 'Kunne ikke importere shader',
			'shaders.deleteShader' => 'Slet shader',
			'shaders.deleteShaderConfirm' => ({required Object name}) => 'Slet "${name}"?',
			'companionRemote.title' => 'Fjernbetjening',
			'companionRemote.connectedTo' => ({required Object name}) => 'Forbundet til ${name}',
			'companionRemote.unknownDevice' => 'Ukendt enhed',
			'companionRemote.session.startingServer' => 'Starter fjernbetjeningsserver...',
			'companionRemote.session.hostAddress' => 'Værtsadresse',
			'companionRemote.session.connected' => 'Forbundet',
			'companionRemote.session.serverRunning' => 'Fjernbetjeningsserver aktiv',
			'companionRemote.session.serverStopped' => 'Fjernbetjeningsserver stoppet',
			'companionRemote.session.serverRunningDescription' => 'Mobile enheder på dit netværk kan oprette forbindelse til denne app',
			'companionRemote.session.serverStoppedDescription' => 'Start serveren for at tillade mobilenheder at oprette forbindelse',
			'companionRemote.session.usePhoneToControl' => 'Brug din mobilenhed til at styre denne app',
			'companionRemote.session.startServer' => 'Start serveren',
			'companionRemote.session.stopServer' => 'Stop serveren',
			'companionRemote.session.minimize' => 'Minimér',
			'companionRemote.session.manualAddressHint' => 'Manuel forbindelsesadresse:',
			'companionRemote.pairing.hostAddressHint' => '192.168.1.100:48632',
			'companionRemote.pairing.connecting' => 'Opretter forbindelse...',
			'companionRemote.pairing.searchingForDevices' => 'Søger efter enheder...',
			'companionRemote.pairing.noDevicesFound' => 'Ingen enheder fundet på dit netværk',
			'companionRemote.pairing.noDevicesHint' => 'Åbn Plezy på din computer, og brug det samme Wi-Fi-netværk',
			'companionRemote.pairing.availableDevices' => 'Tilgængelige enheder',
			'companionRemote.pairing.manualConnection' => 'Manuel forbindelse',
			'companionRemote.pairing.validationHostRequired' => 'Angiv en værtsadresse',
			'companionRemote.pairing.validationHostFormat' => 'Format skal være IP:port (f.eks. 192.168.1.100:48632)',
			'companionRemote.pairing.connectionTimedOut' => 'Forbindelsen fik timeout. Brug samme netværk på begge enheder.',
			'companionRemote.pairing.sessionNotFound' => 'Enhed ikke fundet. Sørg for, at Plezy kører på værten.',
			'companionRemote.pairing.failedToConnect' => ({required Object error}) => 'Kunne ikke oprette forbindelse: ${error}',
			'companionRemote.remote.disconnectConfirm' => 'Vil du afbryde forbindelsen til fjernsessionen?',
			'companionRemote.remote.reconnecting' => 'Genopretter forbindelse...',
			'companionRemote.remote.attemptOf' => ({required Object current}) => 'Forsøg ${current} af 5',
			'companionRemote.remote.retryNow' => 'Prøv igen nu',
			'companionRemote.remote.tabRemote' => 'Fjernbetjening',
			'companionRemote.remote.tabPlay' => 'Afspil',
			'companionRemote.remote.tabMore' => 'Mere',
			'companionRemote.remote.menu' => 'Menu',
			'companionRemote.remote.tabNavigation' => 'Fanenavigation',
			'companionRemote.remote.tabDiscover' => 'Opdag',
			'companionRemote.remote.tabLibraries' => 'Biblioteker',
			'companionRemote.remote.tabSearch' => 'Søg',
			'companionRemote.remote.tabDownloads' => 'Downloads',
			'companionRemote.remote.tabSettings' => 'Indstillinger',
			'companionRemote.remote.previous' => 'Forrige',
			'companionRemote.remote.playPause' => 'Afspil/Pause',
			'companionRemote.remote.next' => 'Næste',
			'companionRemote.remote.seekBack' => 'Spol tilbage',
			'companionRemote.remote.stop' => 'Stop',
			'companionRemote.remote.seekForward' => 'Spol frem',
			'companionRemote.remote.volume' => 'Lydstyrke',
			'companionRemote.remote.volumeDown' => 'Ned',
			'companionRemote.remote.volumeUp' => 'Op',
			'companionRemote.remote.fullscreen' => 'Fuldskærm',
			'companionRemote.remote.subtitles' => 'Undertekster',
			'companionRemote.remote.audio' => 'Lyd',
			'companionRemote.remote.searchHint' => 'Søg på desktop...',
			'companionRemote.errors.noNetworkInterface' => 'Ingen netværksgrænseflade fundet',
			'companionRemote.errors.authenticationFailed' => 'Godkendelse mislykkedes',
			'companionRemote.errors.serverStartFailed' => ({required Object error}) => 'Fjernbetjeningsserveren kunne ikke startes: ${error}',
			'companionRemote.errors.commandFailed' => ({required Object error}) => 'Kunne ikke sende fjernkommando: ${error}',
			'companionRemote.errors.joinTimedOut' => 'Tidsgrænse for deltagelse i session overskredet',
			'companionRemote.errors.failedToConnectAnyAddress' => 'Kunne ikke oprette forbindelse til nogen adresse',
			'companionRemote.errors.connectionLostAfterAttempts' => ({required Object attempts}) => 'Forbindelse mistet efter ${attempts} forsøg',
			'companionRemote.errors.connectionLost' => 'Forbindelse mistet',
			'companionRemote.closedBeforeAuth' => 'Forbindelsen blev lukket før godkendelsen',
			'videoSettings.playbackSpeed' => 'Afspilningshastighed',
			'videoSettings.normalSpeed' => 'Normal',
			'videoSettings.sleepTimerActive' => ({required Object duration}) => 'Aktiv (${duration})',
			'videoSettings.zoom' => 'Zoom',
			'videoSettings.sleepTimer' => 'Sove-timer',
			'videoSettings.audioSync' => 'Lydsynkronisering',
			'videoSettings.subtitleSync' => 'Undertekstsynkronisering',
			'videoSettings.hdr' => 'HDR',
			'videoSettings.hdrUnsupported' => 'HDR er ikke tilgængelig her – denne skrivebordskompositor eller videoudgang kan ikke håndtere det.',
			'videoSettings.hdrToneMapping' => 'HDR-tonemapping',
			'videoSettings.hdrToneMappingCompositor' => 'Kompositor',
			'videoSettings.hdrToneMappingCompositorDescription' => 'Videregiv kildens HDR-metadata, og lad skrivebordskompositoren tonemappe dem.',
			'videoSettings.hdrToneMappingPlayer' => 'Afspiller',
			'videoSettings.hdrToneMappingPlayerDescription' => 'Tilpas til skærmens maksimale lysstyrke i afspilleren, og fortæl derefter kompositoren om resultatet.',
			'videoSettings.hdrToneMappingFailed' => 'Kunne ikke ændre HDR-tonemapping – den tidligere tilstand er stadig aktiv.',
			'videoSettings.audioOutput' => 'Lydoutput',
			'videoSettings.performanceOverlay' => 'Ydelsesoverlay',
			'videoSettings.audioOutputDolbyAtmos' => 'Dolby Atmos',
			'videoSettings.audioOutputDolbyAudio' => 'Dolby Audio',
			'videoSettings.audioOutputSurround' => 'Surround',
			'videoSettings.audioOutputSpatial' => 'Rumlig lyd',
			'videoSettings.audioOutputStereo' => 'Stereo',
			'videoSettings.audioNormalization' => 'Normalisér lydstyrke',
			'videoSettings.audioNormalizationDisablesPassthrough' => 'Dekoder lyd til PCM; passthrough er fra, mens dette er slået til',
			'videoSettings.audioNormalizationStereoMix' => 'Dekoder lyd til en stereomix; passthrough er fra, mens dette er slået til',
			'performanceOverlay.color' => 'Farve',
			'performanceOverlay.performance' => 'Ydeevne',
			'performanceOverlay.buffer' => 'Buffer',
			'performanceOverlay.app' => 'App',
			'performanceOverlay.decoder' => 'Dekoder',
			'performanceOverlay.rawDecoder' => 'Rå dekoder',
			'performanceOverlay.tunneling' => 'Tunneling',
			'performanceOverlay.passthrough' => 'Passthrough',
			'performanceOverlay.aspect' => 'Billedformat',
			'performanceOverlay.rotation' => 'Rotation',
			'performanceOverlay.dvSource' => 'DV-kilde',
			'performanceOverlay.dvPath' => 'DV-sti',
			'performanceOverlay.p7Conversion' => 'P7-konv.',
			'performanceOverlay.sampleRate' => 'Samplingsrate',
			'performanceOverlay.pixelFormat' => 'Pixelformat',
			'performanceOverlay.hwFormat' => 'HW-format',
			'performanceOverlay.matrix' => 'Matrix',
			'performanceOverlay.primaries' => 'Primærfarver',
			'performanceOverlay.transfer' => 'Overførsel',
			'performanceOverlay.renderFps' => 'Gengivelses-FPS',
			'performanceOverlay.displayFps' => 'Skærm-FPS',
			'performanceOverlay.avSync' => 'A/V-synk.',
			'performanceOverlay.dropped' => 'Tabte',
			'performanceOverlay.dvRpus' => 'DV RPU’er',
			'performanceOverlay.dvRpuAverage' => 'DV RPU gns.',
			'performanceOverlay.dvSampleAverage' => 'DV-sample gns.',
			'performanceOverlay.maxLuma' => 'Maks. luma',
			'performanceOverlay.minLuma' => 'Min. luma',
			'performanceOverlay.maxCll' => 'MaxCLL',
			'performanceOverlay.maxFall' => 'MaxFALL',
			'performanceOverlay.cacheUsed' => 'Brugt cache',
			'performanceOverlay.cacheLimit' => 'Cachegrænse',
			'performanceOverlay.speed' => 'Hastighed',
			'performanceOverlay.player' => 'Afspiller',
			'performanceOverlay.memory' => 'Hukommelse',
			'performanceOverlay.uiFps' => 'UI-FPS',
			'performanceOverlay.fps' => 'FPS',
			'performanceOverlay.decoderAndroidHw' => 'Android HW',
			'performanceOverlay.decoderNvidiaHw' => 'NVIDIA HW',
			'performanceOverlay.decoderQualcommHw' => 'Qualcomm HW',
			'performanceOverlay.decoderMediatekHw' => 'MediaTek HW',
			'performanceOverlay.decoderExynosHw' => 'Exynos HW',
			'performanceOverlay.decoderSoftware' => 'Software',
			'performanceOverlay.decoderHardware' => 'Hardware',
			'performanceOverlay.tunnelingActive' => 'Aktiv',
			'performanceOverlay.dvRpuFailed' => ({required Object converted, required Object failures}) => '${converted} (${failures} mislykkedes)',
			'externalPlayer.title' => 'Ekstern afspiller',
			'externalPlayer.useExternalPlayer' => 'Brug ekstern afspiller',
			'externalPlayer.useExternalPlayerDescription' => 'Åbn videoer i en anden app',
			'externalPlayer.selectPlayer' => 'Vælg afspiller',
			'externalPlayer.customPlayers' => 'Brugerdefinerede afspillere',
			_ => null,
		} ?? switch (path) {
			'externalPlayer.systemDefault' => 'Systemstandard',
			'externalPlayer.addCustomPlayer' => 'Tilføj brugerdefineret afspiller',
			'externalPlayer.playerName' => 'Afspillernavn',
			'externalPlayer.playerNameHint' => 'Min afspiller',
			'externalPlayer.playerCommand' => 'Kommando',
			'externalPlayer.playerPackage' => 'Pakkenavn',
			'externalPlayer.playerUrlScheme' => 'URL-skema',
			'externalPlayer.off' => 'Fra',
			'externalPlayer.launchFailed' => 'Kunne ikke åbne ekstern afspiller',
			'externalPlayer.appNotInstalled' => ({required Object name}) => '${name} er ikke installeret',
			'externalPlayer.playInExternalPlayer' => 'Afspil i ekstern afspiller',
			'metadataEdit.artwork' => 'Grafik',
			'metadataEdit.title' => 'Titel',
			'metadataEdit.sortTitle' => 'Sorteringstitel',
			'metadataEdit.originalTitle' => 'Originaltitel',
			'metadataEdit.releaseDate' => 'Udgivelsesdato',
			'metadataEdit.contentRating' => 'Aldersgrænse',
			'metadataEdit.studio' => 'Studie',
			'metadataEdit.tagline' => 'Slogan',
			'metadataEdit.summary' => 'Resumé',
			'metadataEdit.poster' => 'Plakat',
			'metadataEdit.background' => 'Baggrund',
			'metadataEdit.logo' => 'Logo',
			'metadataEdit.imageUrl' => 'Billed-URL',
			'metadataEdit.allEpisodes' => 'Alle episoder',
			'metadataEdit.never' => 'Aldrig',
			'metadataEdit.seasons' => 'Sæsoner',
			'metadataEdit.show' => 'Vis',
			'metadataEdit.hide' => 'Skjul',
			'metadataEdit.subtitleMode' => 'Automatisk valg af undertekster',
			'metadataEdit.tags' => 'Tags',
			'metadataEdit.genre' => 'Genre',
			'metadataEdit.director' => 'Instruktør',
			'metadataEdit.writer' => 'Forfatter',
			'metadataEdit.producer' => 'Producer',
			'metadataEdit.country' => 'Land',
			'metadataEdit.collection' => 'Samling',
			'metadataEdit.label' => 'Etiket',
			'matchScreen.match' => 'Match...',
			'matchScreen.search' => 'Søg',
			'serverTasks.title' => 'Serveropgaver',
			'trakt.title' => 'Trakt',
			'trakt.connected' => 'Forbundet',
			'trakt.connectedAs' => ({required Object username}) => 'Forbundet som @${username}',
			'trakt.disconnectConfirm' => 'Frakobl Trakt-konto?',
			'trakt.disconnectConfirmBody' => 'Plezy stopper med at sende hændelser til Trakt. Du kan tilslutte igen når som helst.',
			'trakt.scrobble' => 'Realtids-scrobbling',
			'trakt.scrobbleDescription' => 'Send afspil-, pause- og stop-begivenheder til Trakt under afspilning.',
			'trakt.watchedSync' => 'Synkroniser set-status',
			'trakt.watchedSyncDescription' => 'Når du markerer elementer som set i Plezy, markeres de også på Trakt.',
			'seerr.title' => 'Seerr',
			'seerr.connectTitle' => 'Forbind Seerr',
			'seerr.serverUrl' => 'Server-URL',
			'seerr.serverUrlHelper' => 'Adressen på din Seerr-instans',
			'seerr.checkServer' => 'Fortsæt',
			'seerr.signInWithLocal' => 'Brug en lokal konto',
			'seerr.email' => 'E-mail',
			'seerr.noSignInMethods' => 'Denne Seerr-instans tilbyder ingen loginmetode, som Plezy understøtter.',
			'seerr.instance' => 'Instans',
			'seerr.disconnectConfirm' => 'Afbryd forbindelsen til Seerr?',
			'seerr.disconnectConfirmBody' => 'Plezy glemmer denne Seerr-instans. Du kan altid oprette forbindelse igen.',
			'seerr.request' => 'Anmod',
			'seerr.request4k' => 'Anmod i 4K',
			'seerr.seasons' => 'Sæsoner',
			'seerr.allSeasons' => 'Alle sæsoner',
			'seerr.advancedOptions' => 'Avanceret',
			'seerr.destinationServer' => 'Destinationsserver',
			'seerr.qualityProfile' => 'Kvalitetsprofil',
			'seerr.rootFolder' => 'Rodmappe',
			'seerr.languageProfile' => 'Sprogprofil',
			'seerr.tags' => 'Tags',
			'seerr.noTags' => 'Ingen tags',
			'seerr.defaultOption' => ({required Object name}) => '${name} (standard)',
			'seerr.animeNote' => 'Denne serie er en anime.',
			'seerr.requestSubmitted' => 'Anmodning sendt',
			'seerr.requestFailed' => ({required Object error}) => 'Anmodning mislykkedes: ${error}',
			'seerr.requestsLoadFailed' => 'Kunne ikke indlæse anmodningsmuligheder',
			'seerr.nothingToRequest' => 'Alt er allerede tilgængeligt eller anmodet.',
			'seerr.statusAvailable' => 'Tilgængelig',
			'seerr.statusPartiallyAvailable' => 'Delvist tilgængelig',
			'seerr.statusRequested' => 'Anmodet',
			'seerr.statusProcessing' => 'Behandler',
			'seerr.statusBlocklisted' => 'På blokeringslisten',
			'seerr.couldNotReach' => ({required Object url, required Object error}) => 'Kunne ikke nå ${url}: ${error}',
			'seerr.noInstanceAtUrl' => ({required Object url, required Object status}) => 'Ingen Seerr-instans på ${url} (HTTP ${status})',
			'seerr.behindAuthProxy' => 'En godkendende reverse proxy (SSO eller HTTP-auth) svarede i stedet for Seerr. Plezy kan ikke logge ind gennem den: Lad Seerrs /api/v1-sti omgå proxyen for denne app, eller brug en adresse, der når Seerr direkte.',
			'seerr.invalidUrl' => 'Indtast en serveradresse som https://seerr.example.com',
			'seerr.notInitialized' => 'Denne Seerr-instans har ikke fuldført førstegangsopsætningen',
			'seerr.noStoredCredentials' => 'Ingen gemte loginoplysninger er tilgængelige til at logge ind igen',
			'seerr.signInRejected' => 'Login blev afvist',
			'seerr.noSessionCookie' => 'Seerr udstedte ikke en sessionscookie',
			'seerr.freshCookieRejected' => 'Seerr afviste den nye sessionscookie',
			'seerr.noUserInformation' => 'Seerr returnerede ikke brugeroplysninger',
			'seerr.sessionRejectedAfterReauth' => 'Sessionen blev afvist efter at være logget ind igen',
			'seerr.permissionDenied' => 'Seerr afviste denne handling: din konto har ikke længere den nødvendige tilladelse',
			'seerr.permissionRevoked' => 'Du har ikke længere tilladelse til at anmode om dette',
			'services.title' => 'Tjenester',
			'services.hubSubtitle' => 'Synkroniser dit visningsfremskridt, og anmod om nye titler.',
			'services.integrations' => 'Integrationer',
			'services.notConnected' => 'Ikke forbundet',
			'services.connectedAs' => ({required Object username}) => 'Forbundet som @${username}',
			'services.scrobble' => 'Registrer fremgang automatisk',
			'services.scrobbleDescription' => 'Opdater din liste, når du er færdig med et afsnit eller en film.',
			'services.disconnectConfirm' => ({required Object service}) => 'Afbryd forbindelsen til ${service}?',
			'services.disconnectConfirmBody' => ({required Object service}) => 'Plezy stopper med at opdatere ${service}. Du kan altid oprette forbindelse igen.',
			'services.connectFailed' => ({required Object service}) => 'Kunne ikke forbinde til ${service}. Prøv igen.',
			'services.names.mal' => 'MyAnimeList',
			'services.names.anilist' => 'AniList',
			'services.names.simkl' => 'Simkl',
			'services.names.seerr' => 'Seerr',
			'services.names.mdblist' => 'MDBList',
			'services.deviceCode.title' => ({required Object service}) => 'Aktiver Plezy på ${service}',
			'services.deviceCode.instructions' => 'Scan QR-koden, eller gå til adressen nedenfor, og indtast denne kode:',
			'services.deviceCode.openToActivate' => ({required Object service}) => 'Åbn ${service} for at aktivere',
			'services.deviceCode.copyCode' => 'Kopiér aktiveringskode',
			'services.deviceCode.waitingForAuthorization' => 'Venter på godkendelse…',
			'services.deviceCode.codeCopied' => 'Kode kopieret',
			'services.oauthProxy.title' => ({required Object service}) => 'Log ind på ${service}',
			'services.oauthProxy.body' => 'Scan denne QR-kode, eller åbn URL\'en på en enhed.',
			'services.oauthProxy.openToSignIn' => ({required Object service}) => 'Åbn ${service} for at logge ind',
			'services.pendingAuth.copyUrl' => 'Kopiér login-URL',
			'services.pendingAuth.urlCopied' => 'URL kopieret',
			'services.libraryFilter.title' => 'Bibliotekfilter',
			'services.libraryFilter.subtitleAllSyncing' => 'Synkroniserer alle biblioteker',
			'services.libraryFilter.subtitleNoneSyncing' => 'Intet synkroniseres',
			'services.libraryFilter.subtitleBlocked' => ({required Object count}) => '${count} blokeret',
			'services.libraryFilter.subtitleAllowed' => ({required Object count}) => '${count} tilladt',
			'services.libraryFilter.mode' => 'Filtertilstand',
			'services.libraryFilter.modeBlacklist' => 'Blokliste',
			'services.libraryFilter.modeWhitelist' => 'Tilladelsesliste',
			'services.libraryFilter.modeHintBlacklist' => 'Synkroniser alle biblioteker undtagen dem, du markerer nedenfor.',
			'services.libraryFilter.modeHintWhitelist' => 'Synkroniser kun de biblioteker, du markerer nedenfor.',
			'services.libraryFilter.libraries' => 'Biblioteker',
			'services.libraryFilter.noLibraries' => 'Ingen biblioteker tilgængelige',
			'addServer.username' => 'Brugernavn',
			'addServer.password' => 'Adgangskode',
			'addServer.signIn' => 'Log ind',
			'addServer.change' => 'Ændr',
			'addServer.required' => 'Påkrævet',
			'addServer.couldNotReachServer' => ({required Object error}) => 'Kunne ikke nå serveren: ${error}',
			'addServer.addConnectionTitle' => 'Tilføj forbindelse',
			'addServer.invalidCredentials' => 'Ugyldigt brugernavn eller ugyldig adgangskode',
			_ => null,
		};
	}
}
