# app-bootstrap-routing (`bootstrap`)

**Effort:** L

## 概述

This subsystem covers cold-start orchestration (main.dart), the Material app + root navigation shell (app.dart), backend/Sentry configuration (config/, backend/), static reference data (data/), and ~25 stateless utility helpers (utils/). Startup runs an async sequence: set image-cache budget, init Sentry (release/profile only), init Supabase with PKCE, init local notifications + timezone DB, open the Drift database, run a one-time SharedPreferences→Drift migration, hydrate all repos (inventory/shopping/recipes/meal-plan/food-log/outbox) into memory for the local-only scope (''), schedule a periodic background sync (WorkManager 15-min), then run a single root ProviderScope that overrides every singleton service/repo with the eagerly-built instances. Routing is a single MaterialApp with a 5-tab IndexedStack shell gated behind an AuthGateScreen; deep links are handled two ways — invite tokens (custom scheme com.kunish.freshpantry://invite/<token>, https .../invite/<token>) and a Supabase OAuth root-callback route — both via onGenerateRoute. Reference data (food categories/aliases/perishability, a ~120-entry food-knowledge keyword table, recipe form presets) and pure-function utils (quantity parse/format with 2-decimal float fix, expiry math, clipboard mojibake repair, invite-token gen/validate/hash, JSON extraction, iOS-style page route) round it out.

## 组件(26)

### lib/main.dart

_Async cold-start entrypoint: configures Sentry, Supabase, notifications, Drift, migration, repo hydration, background sync, then runs the root ProviderScope._

main() async: WidgetsFlutterBinding.ensureInitialized(); GoogleFonts.config.allowRuntimeFetching=false. If kDebugMode → await _runFreshPantry() and return (skip Sentry on debug to avoid env noise). Otherwise SentryConfig.fromEnvironment() then SentryFlutter.init(options){ dsn=cfg.dsn; tracesSampleRate=cfg.tracesSampleRate; replay.sessionSampleRate=cfg.replaySessionSampleRate; replay.onErrorSampleRate=cfg.replayOnErrorSampleRate; privacy.maskAllText=true; privacy.maskAllImages=true; if(cfg.environment.trim().isNotEmpty) options.environment=cfg.environment } with appRunner:_runFreshPantry. 

_runFreshPantry() async sequence (ORDER MATTERS): (1) PaintingBinding.instance.imageCache.maximumSizeBytes = 200<<20 (200MB, white-flash fix). (2) backendConfig=BackendConfig.fromEnvironment(); await Supabase.initialize(url:cfg.supabaseUrl, anonKey:cfg.supabasePublishableKey, authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce)). (3) notificationService=NotificationService(); await notificationService.init(). (4) prefs=await SharedPreferences.getInstance(); adapter=SharedPrefsStorageAdapter(prefs). (5) db=AppDatabase(). (6) await migratePrefsBlobsToDrift(prefs:prefs, db:db). (7) build repos: InventoryRepo(db), ShoppingRepo(db), CustomRecipeRepo(db), MealPlanRepo(db), FoodLogRepo(db), SyncOutboxRepo(db). (8) Hydrate the local-only scope ('') synchronously-prepared: inventoryRepo.hydrate(await inventoryRepo.loadAllFor('')); await inventoryRepo.hydrateHistory(); shoppingRepo.hydrate(await shoppingRepo.loadAllFor('')); customRecipeRepo.hydrate(await customRecipeRepo.loadAllFor('')); mealPlanRepo.hydrate(await mealPlanRepo.loadAllFor('')). (9) food log: cutoff = DateTime.now().toUtc().subtract(foodLogRecentWindow /* Duration(days:90) */).millisecondsSinceEpoch; foodLogRepo.hydrate(await foodLogRepo.loadRecentFor('', sinceMs: cutoff)). (10) await outboxRepo.hydratePending(). (11) await _scheduleBackgroundSync(). (12) runApp(SentryWidget(child: ProviderScope(overrides:[...], child: const FreshPantryApp()))).

ProviderScope overrides (overrideWithValue): notificationServiceProvider→notificationService; appDatabaseProvider→db; sharedPreferencesProvider→prefs; storageAdapterProvider→adapter; inventoryRepoProvider→inventoryRepo; shoppingRepoProvider→shoppingRepo; customRecipeRepoProvider→customRecipeRepo; mealPlanRepoProvider→mealPlanRepo; foodLogRepoProvider→foodLogRepo; syncOutboxRepoProvider→outboxRepo; systemShareSourceProvider→createSystemShareSource(); inviteLinkSourceProvider→createInviteLinkSource(); backendConfigProvider→backendConfig.

_scheduleBackgroundSync(): supportsWorkManager = !kIsWeb && (platform==android || platform==iOS); if not → return (no-op). Else: await Workmanager().initialize(backgroundSyncDispatcher); await Workmanager().registerPeriodicTask(backgroundSyncUniqueName /* 'fresh_pantry.periodic_sync' */, backgroundSyncTask /* 'fresh_pantry.background_sync' */, frequency: Duration(minutes:15), constraints: Constraints(networkType: NetworkType.connected), existingWorkPolicy: ExistingPeriodicWorkPolicy.keep).

### lib/app.dart — FreshPantryApp (MaterialApp + routing)

_Root MaterialApp, localization, theme, deep-link route generation, AuthGate wrapping._

FreshPantryApp extends StatelessWidget; optional `Widget? home` (test injection). build() wraps MaterialApp in AnnotatedRegion<SystemUiOverlayStyle>(value: kAppSystemOverlayStyle). MaterialApp config: onGenerateTitle:_localizedTitle (returns '食材管家' if locale.languageCode=='zh' else 'Fresh Pantry'); debugShowCheckedModeBanner:false; theme: AppTheme.lightTheme; localizationsDelegates: [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate]; supportedLocales: [Locale('en','US'), Locale('zh','CN')]; home:_buildHome(); onGenerateRoute:_generateRoute.

_buildHome({String? initialInviteToken}) = home ?? AuthGateScreen(authenticatedChild: const AppShell(), initialInviteToken: initialInviteToken).

_generateRoute(RouteSettings settings): inviteToken = settings.name==null ? null : inviteTokenFromInput(settings.name!); if inviteToken!=null → return MaterialPageRoute(settings:settings, builder:(_)=>_buildHome(initialInviteToken: inviteToken)). Else if !_isRootAuthCallbackRoute(settings.name) → return null. Else → MaterialPageRoute(settings, builder:(_)=>_buildHome()).

_isRootAuthCallbackRoute(String? routeName): false if null; uri=Uri.tryParse(name); false if null; isRootPath = uri.path.isEmpty || uri.path=='/'; return isRootPath && (uri.hasQuery || uri.hasFragment). (This catches the Supabase PKCE OAuth callback hitting the root URL with ?code=/#fragment.)

### lib/app.dart — AppShell (root tab navigation)

_5-tab IndexedStack shell with sync coordinators, search overlay, sync banner, share-intent handling._

AppShell extends ConsumerStatefulWidget. _screens (order MUST match FkTab): [DashboardScreen(), InventoryScreen(), AddIngredientScreen(), RecipesScreen(), ShoppingListScreen()] (indices 0-4). 

initState: source=ref.read(systemShareSourceProvider); source.consumeInitialText().then(_handleSharedText); _shareTextSubscription = source.incomingTextStream.listen(_handleSharedText). dispose: _shareTextSubscription?.cancel().

_handleSharedText(String? text): if text null/empty or !mounted → return; url=extractUrl(text) (only lanfanapp.com/xiachufang.com hosts); if url==null return; ref.read(navigationProvider.notifier).state=0 (→Home tab); Navigator.of(context).push(fkRoute(builder:(_)=>CustomRecipeFormScreen(prefilledUrl:url))).

build(): ref.watch(notificationSyncProvider) (drives expiry-notification resync as a side effect); currentIndex=ref.watch(navigationProvider); isSearchActive=ref.watch(searchActiveProvider); isHome=currentIndex==FkTab.home (0). pages tree = SyncFlushCoordinator( child: HouseholdContentSync( child: SafeArea(top:!isHome, bottom:false, child: IndexedStack(index:currentIndex, children:_screens)))). Returns AnnotatedRegion<SystemUiOverlayStyle>(value: isHome ? kHeroSystemOverlayStyle : kAppSystemOverlayStyle, child: Scaffold(backgroundColor: AppColors.surface, body: SafeArea(top:false, child: Stack(children:[ Positioned.fill(child:pages), if(isHome) Positioned(top:0,left:0,right:0, height: MediaQuery.paddingOf(context).top, child: const ColoredBox(color: AppColors.primary)) /* opaque status-bar scrim on home */, const Positioned(top:0,left:0,right:0, child: SyncStatusBanner()), if(isSearchActive) const SearchOverlay() ])), extendBody:true, bottomNavigationBar: const BottomNavBar())). NOTE: IndexedStack keeps all 5 screens alive (preserves child State); SafeArea is kept resident and only `top` toggles to avoid rebuild churn that restarts sync subscriptions.

### lib/providers/navigation_provider.dart

_Tab index state + search-active state + shopping-category-to-expand state; FkTab constants; navigateToTab extension._

abstract final class FkTab { static const home=0; fridge=1; add=2; recipes=3; shopping=4 }. navigationProvider = StateProvider<int>((ref)=>FkTab.home). searchActiveProvider = StateProvider<bool>((ref)=>false). shoppingCategoryToExpandProvider = StateProvider<String?>((ref)=>null). extension NavigationRef on WidgetRef { void navigateToTab(int index){ read(navigationProvider.notifier).state=index } }. Uses flutter_riverpod legacy StateProvider. Swift: an @Observable AppRouter with `selectedTab: FkTab`, `searchActive: Bool`, `shoppingCategoryToExpand: String?`.

### lib/widgets/common/bottom_nav_bar.dart

_Custom 5-item bottom bar: 4 icon+label tabs + a center 'add' primary FAB; blurred translucent surface._

_items = [('home','首页'),('fridge','食材'),('add',''),('recipes','菜谱'),('shopping','清单')]. Wrapped in ClipRRect(top corners AppRadius.xxl) → BackdropFilter(blur sigmaX/Y=14) → Container(color: AppColors.surface @ alpha 0.92, top BorderSide AppColors.hair width 0.5) → SafeArea(top:false) → Padding(LTRB sm,sm,sm,xs) → Row(spaceAround, crossAxisAlignment.end). For each (index,item): if index==FkTab.add(2) → _PrimaryFab(onTap: ref.navigateToTab(2)); else _TabButton(active: index==currentIndex, onTap: ref.navigateToTab(index)). _TabButton: Semantics(selected,button,label) → FkAnimatedPressable(haptic: selection) → Column[ FkNavIcon(size 22, color active?primary:outline), 3px gap, Text(label labelSmall w600) ]. _PrimaryFab: Semantics(button,label '添加食材') → FkAnimatedPressable(haptic: light) → Container(width/height = AppSize.profileAvatar - AppSpacing.xs, circle, color primary, boxShadow AppShadows.strong) → FkNavIcon(size AppSize.iconMd+6, color onPrimary, strokeWidth 2). currentIndex=ref.watch(navigationProvider). Swift: a custom TabBar overlay or a SwiftUI TabView with a custom center button; honor reduce-motion + haptics (UIImpactFeedbackGenerator/UISelectionFeedbackGenerator).

### lib/config/backend_config.dart

_Compile-time backend config from --dart-define with validation; carries Supabase URL/key + Fresh Pantry API base URL._

const defaultFreshPantryApiBaseUrl = 'https://api.fresh-pantry.kunish.eu.org'. class BackendConfigException implements Exception { final String message; toString()=>'BackendConfigException: $message' }. class BackendConfig { final String supabaseUrl; supabasePublishableKey; apiBaseUrl; const ctor requires all three. factory fromEnvironment() = BackendConfig(supabaseUrl: String.fromEnvironment('SUPABASE_URL'), supabasePublishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'), apiBaseUrl: String.fromEnvironment('FRESH_PANTRY_API_BASE_URL', defaultValue: defaultFreshPantryApiBaseUrl)).validate(). validate(): throws if supabaseUrl.trim().isEmpty ('SUPABASE_URL is required'); throws if !_isHttpUrl(supabaseUrl); throws if supabasePublishableKey.trim().isEmpty; throws if !_isHttpUrl(apiBaseUrl); returns this. _isHttpUrl(v): Uri.tryParse non-null && hasScheme && scheme in {http,https} && hasAuthority && host nonempty. Swift: build-time config via xcconfig/Info.plist or a Config enum; fail fast at launch if missing.

### lib/config/sentry_config.dart

_Compile-time Sentry config with sample-rate parsing/validation; default DSN baked in._

const defaultSentryDsn = 'https://21d545f97f6b73ed79a31c666318ba7f@o848334.ingest.us.sentry.io/4511468203147264'. class SentryConfigException implements Exception { String message }. class SentryConfig { final String dsn; double tracesSampleRate; double replaySessionSampleRate; double replayOnErrorSampleRate; String environment }. factory fromEnvironment(): reads String.fromEnvironment for SENTRY_TRACES_SAMPLE_RATE (default '1.0'), SENTRY_REPLAY_SESSION_SAMPLE_RATE (default '1.0'), SENTRY_REPLAY_ON_ERROR_SAMPLE_RATE (default '1.0'); dsn = SENTRY_DSN (default defaultSentryDsn); environment = SENTRY_ENVIRONMENT (default ''). Sample rates parsed via _parseSampleRate = double.tryParse(value) ?? double.nan. validate(): if dsn nonempty && !_isHttpUrl(dsn) throw; _validateSampleRate for all three (must be finite && >=0 && <=1 else throw). _isHttpUrl same as BackendConfig. Swift: Sentry Cocoa SDK init in AppDelegate/App init with these params; only enable in release/profile, not debug.

### lib/backend/backend_config_provider.dart

_Riverpod provider returning BackendConfig (overridden in main with the validated instance)._

final backendConfigProvider = Provider<BackendConfig>((ref) => BackendConfig.fromEnvironment()). main() overrides it with overrideWithValue(backendConfig). Swift: inject a Config singleton via environment or a global.

### lib/backend/supabase_client_provider.dart

_Riverpod provider exposing the singleton SupabaseClient._

final supabaseClientProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client). Swift: a shared SupabaseClient created once at launch (Supabase Swift SDK), held by a dependency container.

### lib/data/food_categories.dart

_Canonical 5 food categories + alias normalization + perishability classification._

Canonical: dairyAndEggs='乳品蛋类', freshProduce='果蔬生鲜', meatAndSeafood='肉类海鲜', herbsAndSpices='香料草本', other='其他'. removedPantryStaples='食品柜常备' (legacy, maps to other). values=[dairyAndEggs,freshProduce,meatAndSeafood,herbsAndSpices,other]. _aliases map (every alias→canonical): dairyAndEggs←{乳制品与蛋类,乳制品与干货,乳制品,乳品,蛋类,蛋}; freshProduce←{新鲜蔬果,蔬菜,水果,果蔬,生鲜}; meatAndSeafood←{肉类与海鲜,肉类,海鲜,蛋白质}; herbsAndSpices←{香料与草本,香料,草本,调味品,调味料}; other←{食品柜常备,谷物,主食,干货}. normalize(String? cat): trimmed; if null/empty→null; else _aliases[trimmed] ?? other. dropdownValue(cat)=normalize(cat)??other. _perishable={freshProduce,meatAndSeafood,dairyAndEggs}. isPerishable(cat): n=normalize(cat); if null→false; return _perishable.contains(n). Per ADR-0001 perishables track each Intake as a new Batch; non-perishables merge by name+unit+storage. Swift: an enum FoodCategory with a static alias lookup table and isPerishable computed property.

### lib/data/food_knowledge.dart

_Keyword→smart-defaults lookup (category, storage, shelf-life days), Chinese→English name map, units/shelf-life presets._

class FoodDefaults { final String category; IconType storage; int shelfLifeDays; const ctor }. _entries: ~120 entries keyed by Chinese keyword → FoodDefaults(category, IconType.{fridge|freezer|pantry}, shelfLifeDays). Representative rows: '牛奶'→(乳品蛋类,fridge,7),'酸奶'→(...,14),'奶酪'/'芝士'→(...,30),'黄油'→(...,60),'鸡蛋'/'鸭蛋'/'蛋'→(...,30); produce e.g. '番茄'/'西红柿'→(果蔬生鲜,fridge,7),'土豆'→(...,pantry,21),'洋葱'/'大蒜'→(pantry,30),'豆芽'→(fridge,2); meat e.g. '鸡肉'→(肉类海鲜,fridge,2),'牛排'→(fridge,90),'虾'/'虾仁'→(fridge,90),'饺子'/'馄饨'→(fridge,90); other e.g. '米'/'大米'→(其他,pantry,180),'挂面'/'意面'→(pantry,365),'蜂蜜'→(pantry,730),'罐头'→(pantry,730),'速冻'/'冰淇淋'→(其他,fridge,180); spices e.g. '盐'/'海盐'→(香料草本,pantry,1825),'胡椒'→(pantry,730),'香草'→(fridge,7). (READ FULL FILE for the exact 120 rows.) _englishNames: ~90 Chinese→English entries for API search (e.g. '牛奶'→'milk','鸡胸'→'chicken breast','橄榄油'→'olive oil'). _keyMatches(lower,key): if key.length==1 → lower==key (exact); else lower.contains(key) (substring). englishName(name): longest-matching key wins. lookup(name): longest-matching key wins, returns FoodDefaults?. categoryFor(name,{fallback=other}): FoodCategories.normalize(lookup(name)?.category) ?? FoodCategories.dropdownValue(fallback). isPerishableName(name)=FoodCategories.isPerishable(lookup(name)?.category). shelfLifePresets=[3,7,14,30]. units=['个','瓶','袋','盒','包','g','kg','ml','L']. Depends on IconType from models/storage_area.dart (fridge/freezer/pantry). Swift: a static struct with a [String:FoodDefaults] dictionary + longest-keyword-match helper.

### lib/data/recipe_presets.dart

_Static preset lists for the recipe form (categories, cooking minutes, units)._

class RecipePresets (private ctor). categories=['家常','川菜','粤菜','西式','烘焙','汤羹'] ('+ 其他' appended by wrapper widget). cookingMinutes=[15,30,45,60,90,120] (120 shown as '120+' but writes 120). units=['g','ml','kg','个','把','根','颗','片','杯','勺','适量'] ('自定义…' appended by unit_dropdown). Swift: static let arrays on an enum.

### lib/utils/quantity_text.dart

_Single source of truth for quantity string parse + format (2-decimal float fix)._

_leadingQuantityRe = RegExp(r'^(\d+(?:\.\d+)?)\s*(.*)$') (decimal-only; fraction/range dialect lives in recipe_draft_apply). parseLeadingQuantity(String input) → ({String magnitude, String remainder})? : firstMatch; null if no leading number; magnitude=group(1), remainder=group(2).trim(). formatQuantity(double n) → String: if n==n.roundToDouble() return n.toInt().toString(); else return double.parse(n.toStringAsFixed(2)).toString() — strips trailing-zero/binary-float artifacts (e.g. 1.2000000000000002→'1.2'). Swift: a QuantityText enum with `parseLeading(_:)->(magnitude:String,remainder:String)?` and `format(_ n: Double)->String` using rounding to 2 decimals.

### lib/utils/expiry_calculator.dart

_Calendar-day expiry math and freshness-state classification._

_dateOnly(d)=DateTime(d.year,d.month,d.day). calendarDaysBetween(start,end)=_dateOnly(end).difference(_dateOnly(start)).inDays. daysUntilExpiry(expiry,{now})=calendarDaysBetween(now??DateTime.now(), expiry). expiryFreshness({expiryDate,totalShelfLifeDays,now}): if totalShelfLifeDays<=0 → 0.0; else (daysUntilExpiry/totalShelfLifeDays).clamp(0,1). const urgentWithinDays=2. freshnessStateForExpiry({freshness, expiryDate?, now?}): if expiryDate!=null { days=daysUntilExpiry; if days<0 → FreshnessState.expired; if days<=2 → FreshnessState.urgent }; if freshness>0.5 → fresh; else expiringSoon. expiryLabelFor(expiry,{now}): days<0 → '已过期${-days}天'; days==0 → '今天过期'; days==1 → '明天过期'; else '$days天后过期'. Depends on FreshnessState enum (models/ingredient.dart). Swift: a struct on Calendar with day-granularity diffs.

### lib/utils/ingredient_normalizer.dart

_Normalizes an Ingredient's category + recomputes freshness/expiry label from shelf-life._

normalizeIngredientCategory(item): cat=FoodCategories.normalize(item.category); if cat==item.category return item; else item.copyWith(category:cat). shelfLifeDaysFor(item): if expiryDate null → null; if item.shelfLifeDays!=null&&>0 → that; else FoodKnowledge.lookup(item.name)?.shelfLifeDays if >0; else if item.addedAt null → null; else days=calendarDaysBetween(addedAt,expiry), return days>0?days:null. refreshIngredientFreshness(item,{now}): if expiry null return item; shelfLife=shelfLifeDaysFor(item); if shelfLife null → copyWith(expiryLabel only); else compute freshness=expiryFreshness, copyWith(freshnessPercent, state=freshnessStateForExpiry, expiryLabel). normalizeInventoryIngredient(item)=refreshIngredientFreshness(normalizeIngredientCategory(item)).

### lib/utils/clipboard_text.dart + services/share_intent_service.dart

_Recipe-URL extraction from share intents / clipboard, with UTF-16 mojibake repair and host allowlisting._

clipboard_text: stripNullCharacters(t)=t.replaceAll(' ',''). decodeWidenedUtf16Ascii(t): rebuilds ASCII from code units widened to ascii<<8 (iOS paste bug U+6800→'h'). looksLikeWidenedUtf16Ascii(t): >=4 widened units. normalizeClipboardText(t): strip nulls; if empty return; directUrl=extractUrl; if directUrl!=null && (trimmed==url || looksLikeWidened) return url; decoded=decodeWidenedUtf16Ascii; if changed → extractUrl(decoded) else http-prefix; fallback withoutNulls. normalizePastedRecipeUrl / ensureRecipeUrl: add https://, fix 'vw.'→'www.' host. share_intent_service: kSupportedRecipeHosts={'lanfanapp.com','xiachufang.com'}; isSupportedRecipeHost accepts exact or subdomain (.lanfanapp.com) — rejects lookalikes. extractUrl(text): RegExp(r'https?://[^\s)\]"]+').firstMatch; null unless host is supported. abstract SystemShareSource { Stream<String> incomingTextStream; Future<String?> consumeInitialText() }. Impls: ReceiveSharingIntentSource (android/iOS, uses receive_sharing_intent getMediaStream/getInitialMedia/reset, joins item.path), NoOpShareSource (desktop), InMemoryShareSource (tests). createSystemShareSource(): android/iOS→ReceiveSharingIntentSource else NoOpShareSource. ClipboardUrlDetector: peek()/markIgnored() with 30-min ignore cooldown (used elsewhere, not bootstrap). Swift: a ShareIntentService backed by the iOS Share Extension / app-group + UIPasteboard; same host allowlist + mojibake repair.

### lib/household/invite_token.dart

_Invite-token generation, shape validation, extraction from links/URIs, and SHA-256 hashing._

_random=Random.secure(); _tokenPattern=RegExp(r'^[A-Za-z0-9_-]{10,160}$'). generateInviteToken(): 32 chars from alphabet 'A-Za-z0-9_-'. isInviteTokenShapeValid(t)=_tokenPattern.hasMatch(t). inviteTokenFromInput(input): trim; if shape-valid return it; else parse URI, _inviteTokenFromUri, re-validate. _inviteTokenFromUri(uri): accepts (a) no-scheme path 'invite/<token>' (pathSegments==['invite',token]); (b) http/https with path '/invite/<token>'; (c) custom scheme 'com.kunish.freshpantry' or 'freshpantry' with host=='invite' and single path segment → that segment. hashInviteToken(t)=sha256.convert(utf8.encode(t)).toString(). Swift: use CryptoKit SHA256 + SecRandomCopyBytes; same regex/URL parsing.

### lib/utils/page_transitions.dart + safe_push.dart

_App-wide iOS-style page route honoring reduce-motion; double-tap-safe push._

fkRoute<T>({builder, settings, fullscreenDialog=false}) returns _FkPageRoute (extends CupertinoPageRoute → horizontal slide + left-edge back gesture on all platforms). _FkPageRoute.buildTransitions: if MediaQuery.disableAnimationsOf(context) → FadeTransition(opacity:animation) (no slide, no gesture); else super. safe_push: pushRouteOnce<T>(context,route): if ModalRoute.of(context)?.isCurrent != true → return Future.value() (rejects accidental double-tap second push); else Navigator.push. Swift: standard NavigationStack push; reduce-motion via accessibilityReduceMotion.

### lib/utils — UI helpers (app_dialog, app_snackbar, fk_toast, food_departure_sheet)

_Reusable dialogs/snackbars/toasts and the waste-outcome bottom sheet._

app_dialog: showAppConfirmDialog(context,{title,content,confirmLabel='确认',cancelLabel='取消',isDestructive=false})→Future<bool> (AlertDialog, AppColors.surface bg, AppRadius.xl, PlusJakartaSans title w700, Manrope content; confirm red if destructive; returns result??false). showAppInfoDialog(...,{buttonLabel='好'})→Future<void>. app_snackbar: showAppSnackBar(context,message,{backgroundColor,duration=4s,actionLabel,onAction,actionTextColor,clearPrevious=true,persist=false}); asserts actionLabel&onAction both-or-neither; floating, AppRadius.md. fk_toast: fkToast(context,message): floating SnackBar, check icon AppColors.fkSuccess, white Manrope 13 w500, bg onSurface@0.95, 1800ms, margin LR 50 bottom 110. food_departure_sheet: showFoodDepartureOutcomeSheet(context,{itemName,count=1})→Future<FoodLogOutcome?> — modal sheet titled '「name」要移除' or '移除 N 样食材', two tiles (consumed='吃完 / 用掉了' primary; wasted='没吃完,扔了' error) + 取消; returns FoodLogOutcome.{consumed|wasted} or null. Swift: SwiftUI confirmationDialog / alert / Toast view + a .sheet for the departure outcome.

### lib/utils — formatting/parsing helpers (storage_labels, dashboard_greeting, meal_plan_day_label, food_details_summary, normalize_cache_key, ai_base_url, ai_json_extract, recipe_draft_apply, json_cast, json_object_list)

_Small pure functions for labels, greetings, day labels, summaries, cache keys, AI URL/JSON handling, recipe-draft application, and JSON casting._

storage_labels: storageLabelFor(IconType): fridge→'冰箱', freezer→'冷冻室', pantry→'食品柜'; storageIconFor: fridge→Icons.kitchen, freezer→Icons.ac_unit, pantry→Icons.shelves. dashboard_greeting: dashboardGreetingFor(now) by hour: 5-11→'早安，主厨。',11-14→'午安，主厨。',14-18→'下午好，主厨。',18-23→'晚上好，主厨。', else '夜深了，主厨。'. meal_plan_day_label: mealPlanDayLabel(day,today): dateOnly diff; 0→'今天',1→'明天', else '周'+['一','二','三','四','五','六','日'][weekday-1]. food_details_summary: foodDetailsSummary(details) → 'desc · category · 存储label保存 · 约 N 天' (omits placeholder desc via isPlaceholderFoodDescription; fallback '查看食材详情'). normalize_cache_key: trim().toLowerCase().replaceAll(RegExp(r'\s+'),' '). ai_base_url: normalizeAiBaseUrl(raw): trim, strip trailing '/', strip '/chat/completions' suffix, append '/v1' unless present (OpenAI-compatible). ai_json_extract: extractJsonArrayWithFallbacks / extractJsonObjectWithFallbacks — try direct decode → fenced ```json``` block → inline [..]/{..} regex, type-checked, swallow errors. recipe_draft_apply: classes RecipeDraftApplyResult & AppliedIngredientRow; _quantityRe=RegExp(r'^(\d+(?:[./\-]\d+)?)\s*(.*)$') (handles fraction 1/2, range 2-3, decimal, int); appliedIngredientRowFromDraft splits amount→quantity/unit (unit only if in RecipePresets.units else folded into quantity text); recipeDraftToApplyResult maps a RecipeDraft → result, coverImageSource gated by isSupportedImageSource. json_cast: asJsonMap/asJsonList/asJsonString (safe type casts returning null). json_object_list: decodeJsonObjectList(source) → List<Map<String,dynamic>> (throws FormatException if not a list; keeps only Map entries). Swift: free functions / small enums; AI JSON extraction via Codable + regex fallback.

### lib/services/notification_service.dart

_Local-notification scheduling wrapper (init, permission, schedule, syncAll, cancel) used by bootstrap + expiry resync._

NotificationService({plugin}) wraps FlutterLocalNotificationsPlugin. State: _initialized, _permissionGranted; getters isInitialized/permissionGranted. init({onTap}): if already init return; tz_data.initializeTimeZones(); AndroidInitializationSettings('@mipmap/ic_launcher'); DarwinInitializationSettings(requestAlert/Badge/Sound permission:false — does NOT prompt at init); plugin.initialize(android/iOS/macOS, onDidReceiveNotificationResponse→onTap(id)); _initialized=true; await checkPermission(). requestPermission(): iOS/macOS requestPermissions(alert/badge/sound:true), android requestNotificationsPermission; sets _permissionGranted. checkPermission(): queries OS without prompting; sets _permissionGranted. schedule(ScheduledNotification n): if !init||!granted return; scheduledTz=TZDateTime.from(n.scheduledAt, tz.local); if before now return; recurring = n.kind==dailySummary ? DateTimeComponents.time : null; plugin.zonedSchedule(id,title,body,scheduledTz, AndroidScheduleMode.exactAllowWhileIdle, matchDateTimeComponents:recurring). syncAll(next,{previousIds}): if !init||!granted return; cancel all previousIds then schedule each next. cancel(id). _notifDetails: Android channel 'fresh_pantry_expiry'/'临期提醒' importance/priority high; iOS/macOS DarwinNotificationDetails(). Driven by notificationSyncProvider (NotificationSyncNotifier watches inventory+reminderSettings, computes via ExpiryScheduler.compute, persists ids via scheduledNotificationIdsRepo). Swift: UNUserNotificationCenter; recurring daily via UNCalendarNotificationTrigger(repeats:true); one-shot via UNTimeInterval/Calendar trigger; persist scheduled ids; iOS 26 + UserNotifications.

### lib/services/invite_link_service.dart + providers/invite_link_provider.dart

_Deep-link source for invite URLs (app_links); provider currently defaults to no-op, overridden in main._

abstract InviteLinkSource { Stream<String> incomingLinks; Future<String?> consumeInitialLink() }. AppLinksInviteLinkSource uses app_links: incomingLinks=_appLinks.uriLinkStream.map(toString); consumeInitialLink=_appLinks.getInitialLink()?.toString(). InMemoryInviteLinkSource (tests), NoOpInviteLinkSource (default). createInviteLinkSource()=AppLinksInviteLinkSource(). inviteLinkSourceProvider default = const NoOpInviteLinkSource() (provider override in main supplies the real app_links source). Consumed by AuthGateScreen._listenForInviteLinks (consumeInitialLink + incomingLinks.listen → _handleIncomingInviteLink → inviteTokenFromInput → sets _pendingInviteToken). Swift: handle onOpenURL / UIApplicationDelegate openURL + Universal Links; feed an async stream.

### lib/storage/blob_to_drift_migration.dart

_One-time idempotent import of legacy SharedPreferences blobs into Drift on first launch._

const migratedFlagKey='drift_migrated_v1'. Legacy keys: legacyInventoryKey='inventory_items', legacyShoppingKey='shopping_items', legacyRecipesKey='custom_recipes', legacyOutboxKey='sync_outbox_v1', legacyHistoryKey='add_history'. migratePrefsBlobsToDrift({prefs,db}): if prefs.getBool(migratedFlagKey)==true return. Parse each blob lenient (per-entry try/catch, skip bad): inventory=Ingredient.fromJson filtered name.trim().isNotEmpty; shopping=ShoppingItem.fromJson filtered name nonempty; recipes=Recipe.fromJson filtered id&&name nonempty; ops=SyncOperation.fromJson; history=_decodeMap. Write to local scope '': InventoryRepo(db).saveItems('',inventory); ShoppingRepo(db).saveItems('',shopping); CustomRecipeRepo(db).saveRecipes('',recipes); SyncOutboxRepo(db).replaceAll(ops); if history nonempty InventoryRepo(db).saveHistory(history). Set flag only after ALL writes succeed (mid-flight throw leaves flag unset → retry next launch; legacy blobs left in place one release for rollback). Swift: a one-time SwiftData migration guarded by a UserDefaults flag; only needed if importing from a prior Flutter install (likely N/A for a fresh native rewrite — see openQuestions).

### lib/sync/household_content_sync.dart + sync_flush_coordinator.dart

_Lifecycle widgets in the AppShell tree that drive household content sync and outbox flush on connectivity/foreground edges._

HouseholdContentSync (ConsumerStatefulWidget): owns a HouseholdContentSyncCoordinator(ref); build watches selectedHouseholdIdProvider.trim() and calls _coordinator.syncTo(householdId); dispose disposes coordinator. SyncFlushCoordinator (ConsumerStatefulWidget with WidgetsBindingObserver): _wasOnline=true; initState addObserver; didChangeAppLifecycleState: if resumed → _flush(); build ref.listen(connectivityOnlineProvider): online=next.value??_wasOnline; if online && !_wasOnline → _flush() (offline→online edge); _wasOnline=online. _flush()=ref.read(syncPushPendingProvider)() (coalesced + backoff internally). Swift: observe scenePhase==.active + NWPathMonitor connectivity edges to trigger outbox flush via an actor-based sync coordinator.

### lib/widgets/common/sync_status_banner.dart

_Top-of-shell banner showing offline / pending-sync state._

Watches syncStatusProvider {showBanner, online, pendingCount}. label: showBanner ? (online ? '同步中 · N 条待同步' : pendingCount>0 ? '离线 · N 条待同步' : '离线') : null. AnimatedSize (AppDuration.normal, zero if reduce-motion, AppMotionCurves.standard) → if showBanner: Material(color online?primary:onSurfaceVariant) with SafeArea(bottom:false) Row[ Icon(online?sync:cloud_off, onPrimary), label onPrimary AppFontSize.sm ] else SizedBox.shrink. Swift: a conditional banner view bound to an @Observable SyncStatus.

### lib/theme/app_theme.dart (overlay constants + lightTheme)

_Global system-overlay styles and the Material light theme used by MaterialApp + AppShell._

kAppSystemOverlayStyle: transparent status bar, statusBarBrightness light, statusBarIconBrightness dark, systemNavigationBarColor AppColors.surface, nav icons dark, contrast not enforced. kHeroSystemOverlayStyle: same but statusBarBrightness dark + statusBarIconBrightness light (for the blue hero header on Home). AppTheme.lightTheme: Material3 ColorScheme from AppColors (full surface/container/primary/secondary/tertiary/error tokens), scaffoldBackground=surface, AppTypography.textTheme, AppBarTheme(transparent, elevation 0, scrolledUnderElevation 0, systemOverlayStyle kAppSystemOverlayStyle), card/chip/input/filledButton/textButton themes (stadium borders, AppRadius rounding, no strokes + soft shadows). Both overlay styles must be applied at AnnotatedRegion AND AppBarTheme to control status-bar icon brightness. Swift: a global appearance/Theme; status-bar style toggled per-tab (home uses light content over the blue hero).

## 外部集成

- Supabase (supabase_flutter): Supabase.initialize(url=SUPABASE_URL, anonKey=SUPABASE_PUBLISHABLE_KEY, authOptions=FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce)). Auth = email OTP (6-digit verifyOTP, not magic link). OAuth/PKCE callback returns to the app root URL with ?query/#fragment, caught by _isRootAuthCallbackRoute via onGenerateRoute. supabaseClientProvider exposes Supabase.instance.client.
- Fresh Pantry API (custom backend): default base URL https://api.fresh-pantry.kunish.eu.org, overridable via --dart-define FRESH_PANTRY_API_BASE_URL. Passed to SupabaseRemotePantryRepository(apiBaseUrl) for household content sync (used by background_sync + the sync coordinators).
- Sentry (sentry_flutter): only initialized in release/profile (skipped on kDebugMode). Default DSN baked into sentry_config.dart; traces + replay session + replay on-error sample rates all default 1.0; maskAllText/maskAllImages true; optional SENTRY_ENVIRONMENT. SentryWidget wraps the ProviderScope.
- Local notifications (flutter_local_notifications + timezone): NotificationService.init registers Android channel 'fresh_pantry_expiry' + Darwin settings (no prompt at init), timezone DB initialized; expiry/daily-summary notifications scheduled via zonedSchedule. Notification taps route by integer id (onTap callback).
- WorkManager (workmanager): periodic background outbox drain registered only on android/iOS — task 'fresh_pantry.background_sync', unique 'fresh_pantry.periodic_sync', frequency 15 min, NetworkType.connected, ExistingPeriodicWorkPolicy.keep. Headless dispatcher (backgroundSyncDispatcher, @pragma vm:entry-point) rebuilds config→Supabase→Drift→outbox→SupabaseRemotePantryRepository and drains the outbox.
- Deep links — invite (app_links via AppLinksInviteLinkSource): custom URL scheme com.kunish.freshpantry (iOS CFBundleURLName com.kunish.freshpantry.auth) and 'freshpantry'; invite forms: scheme://invite/<token>, https://<host>/invite/<token>, and bare 'invite/<token>'. No associated-domains entitlement present (no Universal Links yet).
- Share intent (receive_sharing_intent via ReceiveSharingIntentSource): incoming shared text → extractUrl → only lanfanapp.com / xiachufang.com hosts → opens CustomRecipeFormScreen(prefilledUrl).
- SharedPreferences: app prefs + one-time legacy-blob migration source (keys inventory_items/shopping_items/custom_recipes/sync_outbox_v1/add_history, flag drift_migrated_v1).
- Drift (SQLite, AppDatabase): backs all structured persistence; opened once in main and shared via appDatabaseProvider override.
- google_fonts: runtime fetching DISABLED (GoogleFonts.config.allowRuntimeFetching=false) — fonts must be bundled; PlusJakartaSans (titles) + Manrope (body) used.

## Swift 映射

App entry: a SwiftUI `@main struct FreshPantryApp: App` whose init runs the equivalent bootstrap (config validation → Supabase Swift SDK client → UNUserNotificationCenter setup + timezone-aware scheduling → SwiftData ModelContainer open → repo/service registration in a dependency container) before the first scene renders; show a launch/loading view while async hydration completes (mirror AuthGate startup screen). Replace ProviderScope+overrides with an @Observable dependency container injected via .environment(). Config: BackendConfig/SentryConfig become Swift structs read from Info.plist/xcconfig build settings, validated at launch with fatalError-or-overlay on missing values; only init Sentry-Cocoa in release. Routing: one root view that is an AuthGate (an @Observable SessionStore drives login/OTP/household-bootstrap/invite-preview states) wrapping an AppShell; AppShell is a custom TabView (5 tabs: Dashboard, Inventory, Add, Recipes, Shopping) with a center primary 'Add' button — back the selection with an @Observable AppRouter (selectedTab, searchActive). Use NavigationStack per tab; push screens with default iOS slide (fkRoute is already CupertinoPageRoute) and honor accessibilityReduceMotion. Deep links: .onOpenURL handles invite tokens (custom scheme com.kunish.freshpantry / freshpantry, plus https /invite/<token>) and the Supabase auth callback; share-intent via an iOS Share Extension + app-group writing to a shared store that the app drains on activation. Notifications: UserNotifications framework — daily summary as UNCalendarNotificationTrigger(repeats:true), per-item expiry as one-shot triggers; persist scheduled ids and diff on resync (port NotificationSyncNotifier logic to an actor that observes inventory + reminder settings). Background sync: BGTaskScheduler (BGAppRefreshTask/BGProcessingTask, ~15 min, requiresNetworkConnectivity) draining a SwiftData-backed outbox through the Supabase client + Fresh Pantry API; also flush on scenePhase==.active and on NWPathMonitor offline→online edges (port SyncFlushCoordinator). Reference data (FoodCategories, FoodKnowledge, RecipePresets) → static Swift enums/structs with dictionaries + longest-keyword-match. Utils → free functions / small enums; AI JSON extraction via Codable + regex fallback; quantity_text/expiry_calculator → testable structs preserving the exact 2-decimal float fix and calendar-day semantics.

## 迁移注意

Parity-critical invariants: (1) Startup ORDER is load-bearing — repos must be hydrated for the local-only scope '' BEFORE first render so notifiers' synchronous build() sees data (skipping hydrateHistory truncates add-history on first add). (2) Local-only scope is the empty string '' everywhere (migration, hydration, seeds); the active household id is projected separately. (3) image cache 200MB (white-flash fix) — equivalent is bounding decode size + raising the cache budget in native. (4) FreshnessState thresholds: expired if days<0, urgent if days<=2 (urgentWithinDays) regardless of ratio, fresh if ratio>0.5 else expiringSoon — keep calendar-day (not 24h) granularity via _dateOnly. (5) formatQuantity must round to 2 decimals and drop whole-number trailing zeros (single source of truth; don't reintroduce float artifacts). (6) FoodKnowledge keyword match: single-char keys match the whole name only, multi-char keys match as substring, longest key wins — false positives (蛋糕→蛋, 鱼丸→鱼) depend on this. (7) Category normalization: any unknown non-empty category maps to '其他' (not null); null only for empty input. (8) Perishable set {果蔬生鲜,肉类海鲜,乳品蛋类} forces a new Batch per Intake (ADR-0001). (9) Sentry must NOT run in debug. (10) Deep-link invite token shape regex ^[A-Za-z0-9_-]{10,160}$ and the three URI forms must match exactly; hashInviteToken is SHA-256 hex of UTF-8 bytes (server must agree). (11) Auth is 6-digit email OTP (verifyOTP), NOT magic link; the root-callback route handling exists for PKCE/OAuth and must remain. (12) Background sync is best-effort; the dependable path is foreground/reconnect flush — don't rely on BGTask timing for correctness. (13) WorkManager registration uses keep policy to avoid stacking; iOS execution is throttled. (14) MealPlanEntry/labels normalize to local midnight before diffing to avoid today/tomorrow drift. (15) google_fonts runtime fetching is OFF — bundle PlusJakartaSans + Manrope.

## 开放问题

- Is the legacy SharedPreferences→Drift blob migration (blob_to_drift_migration) in-scope for the native rewrite? It only matters for users upgrading from a prior Flutter install; a fresh native app likely has no legacy blobs to import. Need a decision on whether any cross-app data import path (e.g. from the existing Flutter app's storage) is required.
- ExistingPeriodicWorkPolicy/Constraints map imperfectly to BGTaskScheduler — confirm acceptable that iOS background drain is opportunistic and the 15-min cadence is not guaranteed (matches current behavior).
- No associated-domains entitlement is present, so https invite links are not Universal Links today (only the custom scheme + bare 'invite/<token>' deep-link via app_links / share). Confirm whether the native app should add Universal Links (apple-app-site-association) for https://<host>/invite/<token>.
- The notification onTap routes by integer id but main.dart calls notificationService.init() WITHOUT an onTap handler — so notification taps currently do not deep-link to a screen. Confirm desired tap behavior in the native app (route to inventory/expiring view?).
- Several providers (food_details, recipe) still read SharedPreferences directly per comments ("will be migrated in a future ADR") — confirm these become SwiftData/UserDefaults in the rewrite vs. staying split.
- Exact full contents of FoodKnowledge._entries (~120 rows) and _englishNames (~90 rows) and the precise list of every model field (Ingredient, ShoppingItem, Recipe, ScheduledNotification, FoodLogEntry, MealPlanEntry) are defined in other files outside this subsystem — those must be mapped by the models subsystem to reproduce defaults exactly.
