import 'package:provider/provider.dart';

import '../database/app_database.dart';
import '../exceptions/media_server_exceptions.dart';
import '../media/account_preferences.dart';
import '../media/media_server_user_profile.dart';
import '../profiles/active_profile_provider.dart';
import '../providers/account_preferences_controller.dart';
import '../providers/download_provider.dart';
import '../providers/multi_server_provider.dart';
import 'account_preferences_accounts.dart';
import 'account_preferences_repository.dart';
import 'agent_control_protocol.dart';

/// Configuration of existing, explicitly identified resources. Discovery only
/// projects non-secret domain identities; all writes remain with their owners.
class AgentResourceSettingsCommands {
  const AgentResourceSettingsCommands();

  Future<Object?> read(String command, Map<String, dynamic> arguments, AgentCommandContext context) => _safe(() async {
    if (command != 'settings.list' && command != 'settings.get') {
      throw const AgentControlException('unsupportedOperation', 'Unsupported resource settings read.');
    }
    final scope = agentSettingScope(arguments);
    final profileId = _profile(context, scope, requireIdentity: command == 'settings.get');
    final discovery = command == 'settings.list';
    return switch (scope['type']) {
      'account' => _readAccount(arguments, scope, profileId, context, discovery),
      'syncRule' => _readSync(arguments, scope, profileId, context, discovery),
      _ => throw const AgentControlException('unsupportedScope', 'Unsupported resource scope.'),
    };
  });

  Future<AgentSettingMutation> prepare(String command, Map<String, dynamic> arguments, AgentCommandContext context) =>
      _safe(() async {
        if (command != 'settings.set' && command != 'settings.reset') {
          throw const AgentControlException('unsupportedOperation', 'Unsupported resource settings mutation.');
        }
        final scope = Map<String, dynamic>.unmodifiable(agentSettingScope(arguments));
        _profile(context, scope, requireIdentity: true);
        final key = agentString(arguments, 'key');
        final reset = command == 'settings.reset';
        if (!reset && !arguments.containsKey('value')) {
          throw const AgentControlException('invalidArguments', 'value is required.');
        }
        return switch (scope['type']) {
          'account' => _prepareAccount(key, scope, arguments['value'], reset, context),
          'syncRule' => _prepareSync(key, scope, arguments['value'], reset, context),
          _ => throw const AgentControlException('unsupportedScope', 'Unsupported resource scope.'),
        };
      });

  String _profile(AgentCommandContext context, Map<String, dynamic> scope, {required bool requireIdentity}) {
    context.checkCurrent(requireProfile: true);
    final profileId = context.context.read<ActiveProfileProvider>().activeId;
    if (profileId == null) throw const AgentControlException('noActiveSession', 'An active profile is required.');
    if (requireIdentity) agentString(scope, 'profileId');
    if (scope.containsKey('profileId') && scope['profileId'] != profileId) {
      throw const AgentControlException('sessionChanged', 'The resource belongs to a different profile.');
    }
    return profileId;
  }

  void _scopeFields(Map<String, dynamic> scope, Set<String> fields) {
    if (scope.keys.any((key) => key != 'type' && key != 'profileId' && !fields.contains(key))) {
      throw const AgentControlException('invalidArguments', 'Unexpected resource scope field.');
    }
  }

  Future<Object?> _readAccount(
    Map<String, dynamic> arguments,
    Map<String, dynamic> scope,
    String profileId,
    AgentCommandContext context,
    bool list,
  ) async {
    _scopeFields(scope, {'accountId'});
    final controller = context.context.read<AccountPreferencesController>();
    if (list && !scope.containsKey('accountId')) {
      return {
        'scope': {'type': 'account', 'profileId': profileId},
        'settings': <Object?>[],
        'targets': [
          for (final account in controller.accounts)
            {
              'scope': {'type': 'account', 'profileId': profileId, 'accountId': account.ref.key},
              'label': account.target.label,
              'backend': account.ref.backend.id,
            },
        ],
      };
    }
    final target = _account(scope, context);
    final capabilities = target.controller.repository.capabilitiesFor(target.account.ref);
    if (list) {
      return {
        'scope': scope,
        'settings': [for (final key in AccountPreferenceKey.values) _accountDescriptor(key, capabilities)],
      };
    }
    final key = _accountKey(agentString(arguments, 'key'));
    _requireAccountSupport(key, capabilities);
    final snapshot = await target.controller.repository.load(target.account.ref, forceRefresh: true);
    target.guard();
    return _result(key.name, scope, _jsonValue(snapshot[key]), _accountTiming(key));
  }

  ({AccountPreferencesController controller, AccountPreferenceAccount account, void Function() guard}) _account(
    Map<String, dynamic> scope,
    AgentCommandContext context,
  ) {
    _scopeFields(scope, {'accountId'});
    _profile(context, scope, requireIdentity: true);
    final id = agentString(scope, 'accountId');
    final controller = context.context.read<AccountPreferencesController>();
    final account = controller.accounts.where((account) => account.ref.key == id).firstOrNull;
    if (account == null) {
      throw const AgentControlException('resourceNotFound', 'Account is not editable by this profile.');
    }
    final current = controller.captureAccountIdentity(account);
    void guard() {
      _profile(context, scope, requireIdentity: true);
      if (!current()) throw const AgentControlException('sessionChanged', 'Account identity changed.');
    }

    return (controller: controller, account: account, guard: guard);
  }

  Future<AgentSettingMutation> _prepareAccount(
    String name,
    Map<String, dynamic> scope,
    Object? raw,
    bool reset,
    AgentCommandContext context,
  ) async {
    final target = _account(scope, context);
    final key = _accountKey(name);
    final capabilities = target.controller.repository.capabilitiesFor(target.account.ref);
    _requireAccountSupport(key, capabilities);
    if (reset && key.valueKind != AccountPreferenceValueKind.languageCode) {
      throw const AgentControlException('unsupportedOperation', 'This account preference has no inherited reset.');
    }
    final value = _decodeAccount(key, reset ? null : raw);
    final patch = AccountPreferencesPatch.of(key, value);
    capabilities.validate(patch);
    return _mutation(name, scope, () async {
      target.guard();
      final updated = await target.controller.repository.update(target.account.ref, patch, checkCurrent: target.guard);
      target.guard();
      return _result(name, scope, _jsonValue(updated[key]), _accountTiming(key), persisted: true);
    });
  }

  AccountPreferenceKey _accountKey(String name) =>
      AccountPreferenceKey.values.where((key) => key.name == name).firstOrNull ??
      (throw const AgentControlException('unknownSetting', 'Unknown account preference.'));

  void _requireAccountSupport(AccountPreferenceKey key, AccountPreferencesCapabilities capabilities) {
    if (!capabilities.supports(key)) {
      throw const AgentControlException('unsupportedSetting', 'This backend does not support the account preference.');
    }
  }

  String _accountTiming(AccountPreferenceKey key) => switch (key) {
    AccountPreferenceKey.preferredAudioLanguage ||
    AccountPreferenceKey.autoSelectAudio ||
    AccountPreferenceKey.preferredSubtitleLanguage ||
    AccountPreferenceKey.subtitleMode => 'nextPlayback',
    _ => 'nextCatalogRefresh',
  };

  Map<String, dynamic> _accountDescriptor(AccountPreferenceKey key, AccountPreferencesCapabilities capabilities) => {
    'key': key.name,
    'type': switch (key.valueKind) {
      AccountPreferenceValueKind.boolean => 'boolean',
      AccountPreferenceValueKind.languageCode => 'string',
      _ => 'enum',
    },
    'nullable': key.valueKind == AccountPreferenceValueKind.languageCode,
    'default': null,
    'defaultMeaning': key.valueKind == AccountPreferenceValueKind.languageCode ? 'noPreference' : 'serverOwned',
    'resetSupported': capabilities.supports(key) && key.valueKind == AccountPreferenceValueKind.languageCode,
    if (key.valueKind == AccountPreferenceValueKind.languageCode)
      'constraints': {'format': 'ISO-639-1-or-backend-language-code'},
    'choices': ?_accountChoices(key, capabilities),
    'applicability': {
      'supported': capabilities.supports(key),
      if (!capabilities.supports(key)) 'reason': 'Not supported by this account backend.',
    },
    'application': _accountTiming(key),
    'storage': 'serverAccount',
  };

  List<String>? _accountChoices(AccountPreferenceKey key, AccountPreferencesCapabilities capabilities) =>
      switch (key.valueKind) {
        AccountPreferenceValueKind.subtitleMode => capabilities.subtitleModes.map((value) => value.name).toList(),
        AccountPreferenceValueKind.watchedIndicator => WatchedIndicatorScope.values.map((value) => value.name).toList(),
        AccountPreferenceValueKind.mediaReviewsVisibility =>
          MediaReviewsVisibility.values.map((value) => value.name).toList(),
        AccountPreferenceValueKind.subtitleAccessibility =>
          SubtitleAccessibilityPreference.values.map((value) => value.name).toList(),
        AccountPreferenceValueKind.forcedSubtitles =>
          ForcedSubtitlePreference.values.map((value) => value.name).toList(),
        _ => null,
      };

  Object? _decodeAccount(AccountPreferenceKey key, Object? value) => switch (key.valueKind) {
    AccountPreferenceValueKind.boolean || AccountPreferenceValueKind.languageCode => value,
    AccountPreferenceValueKind.subtitleMode => _enumValue(SubtitlePlaybackMode.values, value),
    AccountPreferenceValueKind.watchedIndicator => _enumValue(WatchedIndicatorScope.values, value),
    AccountPreferenceValueKind.mediaReviewsVisibility => _enumValue(MediaReviewsVisibility.values, value),
    AccountPreferenceValueKind.subtitleAccessibility => _enumValue(SubtitleAccessibilityPreference.values, value),
    AccountPreferenceValueKind.forcedSubtitles => _enumValue(ForcedSubtitlePreference.values, value),
  };

  T _enumValue<T extends Enum>(List<T> values, Object? value) =>
      values.where((entry) => entry.name == value).firstOrNull ??
      (throw const AgentControlException('invalidArguments', 'Unknown account preference choice.'));

  Object? _jsonValue(Object? value) => value is Enum ? value.name : value;

  Future<Object?> _readSync(
    Map<String, dynamic> arguments,
    Map<String, dynamic> scope,
    String profileId,
    AgentCommandContext context,
    bool list,
  ) async {
    _scopeFields(scope, {'serverId', 'ruleId'});
    final downloads = context.context.read<DownloadProvider>();
    final servers = context.context.read<MultiServerProvider>();
    await downloads.ensureInitialized();
    context.checkCurrent(requireProfile: true);
    if (list && !scope.containsKey('ruleId')) {
      if (scope.containsKey('serverId') && !servers.expectedServerIds.contains(agentString(scope, 'serverId'))) {
        throw const AgentControlException('serverUnavailable', 'Server is not bound to the active profile.');
      }
      return {
        'scope': scope,
        'settings': <Object?>[],
        'applicability': {
          'supported': downloads.syncRulesSupported,
          if (!downloads.syncRulesSupported) 'reason': 'Downloads are not supported on this platform.',
        },
        'targets': [
          for (final rule in downloads.syncRules.values)
            if (rule.profileId == profileId &&
                servers.expectedServerIds.contains(rule.serverId) &&
                (!scope.containsKey('serverId') || scope['serverId'] == rule.serverId))
              {
                'scope': {
                  'type': 'syncRule',
                  'profileId': profileId,
                  'serverId': rule.serverId,
                  'ruleId': '${rule.id}',
                },
                'itemId': rule.ratingKey,
                'targetType': rule.targetType,
                'enabled': rule.enabled,
              },
        ],
      };
    }
    final rule = _syncRule(scope, context);
    if (list) {
      return {
        'scope': scope,
        'settings': [
          for (final descriptor in _syncDescriptors(rule))
            if (downloads.syncRulesSupported)
              descriptor
            else
              {
                ...descriptor,
                'resetSupported': false,
                'applicability': {'supported': false, 'reason': 'Downloads are not supported on this platform.'},
              },
        ],
      };
    }
    final key = agentString(arguments, 'key');
    _syncDescriptor(rule, key);
    return _result(key, scope, _syncValue(rule, key), 'nextSync');
  }

  SyncRuleItem _syncRule(Map<String, dynamic> scope, AgentCommandContext context) {
    _scopeFields(scope, {'serverId', 'ruleId'});
    final profileId = _profile(context, scope, requireIdentity: true);
    final serverId = agentString(scope, 'serverId');
    final ruleId = agentString(scope, 'ruleId');
    if (!context.context.read<MultiServerProvider>().expectedServerIds.contains(serverId)) {
      throw const AgentControlException('serverUnavailable', 'Server is not bound to the active profile.');
    }
    final rule = context.context
        .read<DownloadProvider>()
        .syncRules
        .values
        .where((rule) => '${rule.id}' == ruleId && rule.serverId == serverId && rule.profileId == profileId)
        .firstOrNull;
    if (rule == null) throw const AgentControlException('resourceNotFound', 'Sync rule was not found in this profile.');
    return rule;
  }

  List<Map<String, dynamic>> _syncDescriptors(SyncRuleItem rule) {
    final list = rule.targetType == 'collection' || rule.targetType == 'playlist';
    return [
      _descriptor(
        'count',
        'integer',
        null,
        supported: !list,
        reset: false,
        constraints: {'minimum': 0, 'zeroMeaning': 'allUnwatched'},
      ),
      _descriptor('filter', 'enum', 'unwatched', supported: list, choices: ['all', 'unwatched']),
      _descriptor('enabled', 'boolean', true),
      _descriptor('includeSpecials', 'boolean', true, supported: rule.targetType == 'show'),
      _descriptor(
        'version',
        'object',
        {'index': 0},
        supported: !list,
        constraints: {
          'properties': {
            'index': {'type': 'integer', 'minimum': 0},
          },
          'meaning': 'Preferred version index for future episodes; existing per-episode fallback remains in effect.',
        },
      ),
    ];
  }

  Map<String, dynamic> _descriptor(
    String key,
    String type,
    Object? defaultValue, {
    bool supported = true,
    bool reset = true,
    List<String>? choices,
    Map<String, dynamic>? constraints,
  }) => {
    'key': key,
    'type': type,
    'default': defaultValue,
    'resetSupported': reset && supported,
    'application': 'nextSync',
    'applicability': {'supported': supported, if (!supported) 'reason': 'Not consumed by this sync-rule type.'},
    'choices': ?choices,
    'constraints': ?constraints,
  };

  Map<String, dynamic> _syncDescriptor(SyncRuleItem rule, String key) {
    final descriptor = _syncDescriptors(rule).where((entry) => entry['key'] == key).firstOrNull;
    if (descriptor == null) throw const AgentControlException('unknownSetting', 'Unknown sync-rule setting.');
    if ((descriptor['applicability'] as Map)['supported'] != true) {
      throw const AgentControlException('unsupportedSetting', 'This option is not used by this sync-rule type.');
    }
    return descriptor;
  }

  Object _syncValue(SyncRuleItem rule, String key) => switch (key) {
    'count' => rule.episodeCount,
    'filter' => rule.downloadFilter,
    'enabled' => rule.enabled,
    'includeSpecials' => rule.includeSpecials,
    'version' => {'index': rule.mediaIndex},
    _ => throw const AgentControlException('unknownSetting', 'Unknown sync-rule setting.'),
  };

  Future<AgentSettingMutation> _prepareSync(
    String key,
    Map<String, dynamic> scope,
    Object? raw,
    bool reset,
    AgentCommandContext context,
  ) async {
    final downloads = context.context.read<DownloadProvider>();
    if (!downloads.syncRulesSupported) {
      throw const AgentControlException('unsupportedSetting', 'Downloads are not supported on this platform.');
    }
    await downloads.ensureInitialized();
    final rule = _syncRule(scope, context);
    final descriptor = _syncDescriptor(rule, key);
    if (reset && descriptor['resetSupported'] != true) {
      throw const AgentControlException('unsupportedOperation', 'This sync option has no reset default.');
    }
    final value = reset ? descriptor['default'] : raw;
    int? count;
    String? filter;
    bool? enabled;
    bool? specials;
    int? version;
    switch (key) {
      case 'count':
        count = _nonnegativeInt(value, 'count');
      case 'filter':
        if (value != 'all' && value != 'unwatched') {
          throw const AgentControlException('invalidArguments', 'filter must be all or unwatched.');
        }
        filter = value as String;
      case 'enabled':
        enabled = _boolean(value, key);
      case 'includeSpecials':
        specials = _boolean(value, key);
      case 'version':
        final object = agentObject(value, 'version');
        if (object.length != 1) throw const AgentControlException('invalidArguments', 'version requires only index.');
        version = _nonnegativeInt(object['index'], 'version.index');
    }
    DownloadProvider.validateSyncRuleOptions(
      rule,
      episodeCount: count,
      downloadFilter: filter,
      includeSpecials: specials,
      mediaIndex: version,
    );
    void guard() {
      final current = _syncRule(scope, context);
      if (current.id != rule.id || current.globalKey != rule.globalKey) {
        throw const AgentControlException('resourceNotFound', 'Sync rule identity changed.');
      }
    }

    return _mutation(key, scope, () async {
      guard();
      final updated = await downloads.updateSyncRuleOptions(
        rule.globalKey,
        episodeCount: count,
        downloadFilter: filter,
        enabled: enabled,
        includeSpecials: specials,
        mediaIndex: version,
        checkCurrent: guard,
      );
      guard();
      return _result(key, scope, _syncValue(updated, key), 'nextSync', persisted: true);
    });
  }

  int _nonnegativeInt(Object? value, String name) {
    if (value is! int || value < 0) {
      throw AgentControlException('invalidArguments', '$name must be a nonnegative integer.');
    }
    return value;
  }

  bool _boolean(Object? value, String name) {
    if (value is! bool) throw AgentControlException('invalidArguments', '$name must be a boolean.');
    return value;
  }

  AgentSettingMutation _mutation(
    String key,
    Map<String, dynamic> scope,
    Future<Map<String, dynamic>> Function() apply,
  ) => AgentSettingMutation(key: key, scope: scope, apply: () => _safe(apply, mutation: true));

  Map<String, dynamic> _result(
    String key,
    Map<String, dynamic> scope,
    Object? value,
    String application, {
    bool? persisted,
    Map<String, dynamic> extra = const {},
  }) => {'key': key, 'scope': scope, 'value': value, 'application': application, 'persisted': ?persisted, ...extra};

  Future<T> _safe<T>(Future<T> Function() action, {bool mutation = false}) async {
    try {
      return await action();
    } on AgentControlException catch (error) {
      if (!mutation) rethrow;
      throw AgentControlException(error.code, error.message, details: {...?error.details, 'stateMayHaveChanged': true});
    } on AccountPreferencesUnavailableException {
      throw AgentControlException(
        'serverUnavailable',
        'Account preferences are currently unavailable.',
        details: {if (mutation) 'stateMayHaveChanged': true},
      );
    } on SyncRuleCleanupBusyException {
      throw const AgentControlException('resourceBusy', 'Sync rules are currently executing or being removed.');
    } on UnsupportedError {
      throw const AgentControlException(
        'unsupportedOperation',
        'The resource does not support this option or operation.',
      );
    } on ArgumentError {
      throw const AgentControlException('invalidArguments', 'Invalid resource configuration value.');
    } on MediaServerHttpException catch (error) {
      throw AgentControlException(
        error.statusCode == 401 || error.statusCode == 403 ? 'permissionDenied' : 'serverRequestFailed',
        'The server did not complete the resource request.',
        details: {'statusCode': error.statusCode, if (mutation) 'stateMayHaveChanged': true},
      );
    } catch (_) {
      throw AgentControlException(
        mutation ? 'mutationFailed' : 'readFailed',
        mutation ? 'The resource update could not be confirmed.' : 'The resource configuration could not be read.',
        details: {if (mutation) 'stateMayHaveChanged': true},
      );
    }
  }
}
