# widgets-design-system (`widgets`)

**Effort:** XL

## 概述

The Fresh Pantry design system is a token layer (lib/theme/) plus a reusable widget library (lib/widgets/) built to mirror a hand-drawn "FreshKeeper" Figma spec (referenced as ui.jsx / screens-*.jsx). The theme provides a warm-cream Material 3 ColorScheme with cornflower-blue primary, butter-yellow warn, coral danger, plus radius/spacing/shadow/motion/typography tokens (typography via google_fonts: Plus Jakarta Sans for display/headlines, Manrope for body/labels). The widget library is organized into FK primitives (fk_* prefix: cards, pills, badges, icon buttons, hero header, dashed border, image placeholder, skeletons), animated primitives (FkAnimatedPressable, FkEntrance, FkShimmer, FkCheckCircle — all reduce-motion aware), urgency/status indicators (FkStatus enum + kFkStatusStyles map + FreshnessState->FkStatus mapping), cartoon SVG icon sets (9 food categories, 5 storage zones, 5 nav tabs), and feature cards (recipe, ingredient, dashboard entry cards). A single source of truth (FkStatus/kFkStatusStyles, FkCategoryPalette) prevents per-screen hardcoding of urgency colors. This defines the SwiftUI design system + component layer for the rewrite.

## 组件(65)

### lib/theme/app_colors.dart

_All color constants (no dynamic theme; light only)._

class AppColors, all `static const Color`. Primary family: primary 0xFF5B7FD4, primaryContainer 0xFF3F60B5, onPrimary FFFFFF, onPrimaryContainer E5ECFA, primaryFixed E5ECFA, primaryLight 8AA3E0, primarySoft E5ECFA. Warn (临期): secondary FFC857, secondaryContainer FFF3D6, onSecondary 2D2438, onSecondaryContainer 9B7A2A, secondaryFixed FFF3D6. Danger (过期/不足, reuses tertiary names): tertiary E76F51, tertiaryContainer FBE0D7, onTertiary FFFFFF, onTertiaryContainer B5523A, tertiaryFixedDim FFC857. Semantic aliases: fkWarn=secondary, fkWarnSoft=secondaryContainer, fkDanger=tertiary, fkDangerSoft=tertiaryContainer, fkSuccess 0xFF5CC9A7 (toast check), fkAlert 0xFFE5484D (pure-red badge dots, distinct from coral danger), fkWarnInk 0xFFB26A1F (临期 fire label). Error mirrors tertiary: error E76F51, errorContainer FBE0D7, onError FFFFFF, onErrorContainer B5523A. Surfaces (warm cream): surface FBF8F3, surfaceDim E8E3DA, surfaceBright FFFFFF, surfaceContainerLowest FFFFFF, surfaceContainerLow F6F2EB, surfaceContainer F0EBE3, surfaceContainerHigh E9E2D6, surfaceContainerHighest E3DCCB. On-surface (plum-ink): onSurface 2D2438, onSurfaceVariant 4F4358, outline 9B92A5, outlineVariant C7C1CE, hair 0x142D2438 (~8% ink hairline). switchTrackOff D9DDD8. urgentAttentionBackground FBE0D7, onTertiaryFixedDim 9B7A2A. Inverse: inverseSurface 2D2438, inverseOnSurface F6F2EB, inversePrimary 8AA3E0. AI: aiAccent=primary, aiAccentMuted=outline, aiGradientStart=primary, aiGradientEnd=primaryContainer. Overlays: onImageScrim 0x33000000, onImageBorderStrong 0xB3FFFFFF, onImageBorderSoft 0x99FFFFFF, modalBarrier 0x47000000, subtleShadow 0x0F000000, shadowWarm 0x293C2D1E (warm brown ~16%), shadowSoft 0x0A263A34. Swift: use a Color extension/asset catalog; ARGB hex with leading-FF = opaque. 0x14/0x29/0x0A etc are alpha bytes (0x14=20/255≈0.078).

### lib/theme/app_radius.dart

_Corner radius tokens._

class AppRadius static const double: xs 4, sm 8, md 12, lg 16, xl 20 (FK main card / dialog), xxl 24, hero 28 (hero block bottom corners), chip 14 (search field/chip rect), pill 999 (stadium/capsule). Swift: enum of CGFloat; pill -> Capsule().

### lib/theme/app_spacing.dart

_Spacing scale (logical px)._

class AppSpacing static const double: xs 4, sm 8, md 12, lg 16, xl 20, xxl 24 (screen page margin), xxxl 28, huge 32.

### lib/theme/app_sizes.dart

_Misc fixed sizes._

class AppSize static const double: iconSm 18, iconMd 20, settingsIconBox 32, profileAvatar 56.

### lib/theme/app_shadows.dart

_Box-shadow tokens._

class AppShadows static const List<BoxShadow>: card = [shadowSoft blur2 offset(0,1), shadowSoft blur16 offset(0,4)] (FkCard 2-layer). soft = [shadowSoft blur12 offset(0,4)] (icon button/stat card). strong = [shadowWarm blur18 offset(0,6)] (primary FAB/center nav). Swift: SwiftUI .shadow needs one per modifier; chain two .shadow() for `card`, or use a custom ViewModifier.

### lib/theme/app_motion.dart

_Animation duration/curve/param tokens._

AppDuration: fast 120ms (press/micro), normal 180ms (collapse/state), slow 250ms (entrance/cross-fade), page 240ms, shimmer 1400ms. AppMotionCurves: standard=Curves.easeOutCubic, decelerate=Curves.easeOut, emphasized=Cubic(0.2,0,0,1). AppMotion: pressScale 0.97, entranceOffset 8 (px up), staggerStep 50ms, staggerMaxItems 8. Swift: easeOutCubic ≈ .easeOut or custom UnitCurve; map ms to Double seconds.

### lib/theme/app_typography.dart

_Text styles via google_fonts (Plus Jakarta Sans + Manrope) + font-size tokens._

AppFontSize: xs 11, sm 12, md 14, lg 16, xl 20, xxl 24, xxxl 28, huge 32. AppTypography.textTheme (Material TextTheme): displayLarge JakartaSans 32/w800, displayMedium 28/w800, displaySmall 24/w800, headlineLarge JakartaSans 28/w700, headlineMedium 24/w700, headlineSmall 20/w700, titleLarge JakartaSans 20/w600, titleMedium Manrope 16/w600, titleSmall Manrope 14/w600, bodyLarge Manrope 16/w400, bodyMedium Manrope 14/w400, bodySmall Manrope 12/w400, labelLarge Manrope 14/w700, labelMedium Manrope 12/w600, labelSmall Manrope 11/w600. Extra getters: sectionTitle = titleMedium w800; heroStat = JakartaSans 56/w800 letterSpacing -1 height 1; heroSubStat = JakartaSans 28/w800 letterSpacing -0.4; sectionTitleLg = JakartaSans 22/w700 letterSpacing -0.3. Also FkImagePlaceholder uses JetBrains Mono 10. Swift: bundle Plus Jakarta Sans + Manrope (+ JetBrains Mono) as custom fonts; build a Font/TextStyle factory mirroring these sizes/weights. google_fonts fetches at runtime — for Swift bundle the TTFs.

### lib/theme/fk_category_palette.dart

_9 food-category color pairs (tint bg + ink stroke/text)._

class FkCatColors {Color tint; Color ink}. FkCategoryPalette static const: veg(E8F3E1,4F7A3A), fruit(FBE0D7,B5523A), meat(FDD6CE,A8442C), sea(D6EBF2,3F7691), dairy(E5ECFA,3F60B5), drink(E2EAF5,4A5E91), sauce(F0EBE3,7A6748), grain(FFF3D6,9B7A2A), snack(FBE3CE,A85F2C). Map<String,FkCatColors> all keyed by these 9 ids; of(catId) returns all[catId] ?? grain (grain is the default fallback). Swift: enum FoodCategoryStyle with tint/ink Colors; default .grain.

### lib/theme/app_theme.dart

_Material ThemeData assembly + system overlay styles. Barrel-exports all theme files._

Exports app_colors/radius/shadows/spacing/sizes/typography/motion. kAppSystemOverlayStyle: transparent status bar, dark status icons, surface nav bar, dark nav icons (for cream pages). kHeroSystemOverlayStyle: same but LIGHT status icons (dashboard hero gradient bleeds behind status bar). AppTheme.lightTheme: useMaterial3 true, full ColorScheme(brightness light) wired from AppColors, scaffoldBackground surface, textTheme from AppTypography. AppBarTheme transparent/elevation0/scrolledUnderElevation0 + kAppSystemOverlayStyle. cardTheme elevation0 radius xl color surfaceContainerLowest shadowColor shadowSoft margin zero. chipTheme StadiumBorder bg surfaceContainer selected primary label labelLarge no checkmark no side. inputDecorationTheme filled fillColor surfaceContainer, border/enabled radius chip no side, focused radius chip border primary 1.5, contentPadding h14 v12. filledButtonTheme StadiumBorder padding h24 v16. textButtonTheme StadiumBorder. Swift: this maps to global SwiftUI .tint(primary), background, custom button/textfield styles; status-bar control via UIApplication/preferredStatusBarStyle or .toolbarColorScheme. Light mode only — force .preferredColorScheme(.light).

### lib/widgets/shared/fk_pressable.dart (FkAnimatedPressable)

_Universal tap wrapper: press-scale + haptics, reduce-motion aware._

enum HapticKind {selection, light, none}. Props: child, onTap?, onLongPress?, pressedScale=0.97, haptic=selection, behavior=HitTestBehavior.opaque. selection->HapticFeedback.selectionClick, light->lightImpact. enabled = onTap!=null||onLongPress!=null. reduceMotion (MediaQuery.disableAnimationsOf) -> skip scale, plain GestureDetector (still taps+haptics). Else AnimatedScale to pressedScale on tapDown, duration fast(120ms) curve easeOutCubic. Swift: a Button/.onTapGesture style with .scaleEffect bound to @GestureState isPressed + .animation; UIImpactFeedbackGenerator/.sensoryFeedback. Honor UIAccessibility.isReduceMotionEnabled.

### lib/widgets/shared/fk_entrance.dart (FkEntrance)

_One-shot list-item entrance: fade + 8px slide-up with index stagger._

Props: child, index=0, duration?(default slow 250ms). On first didChangeDependencies: if reduceMotion set controller=1.0 (instant); else delay = staggerStep(50ms) * index.clamp(0, staggerMaxItems 8) then forward. Build: reduceMotion -> Opacity(1). Else AnimatedBuilder: Opacity(_opacity) + Transform.translate(offset (1-opacity)*8 up). Plays once per element (not on re-scroll). Swift: .opacity/.offset with .onAppear-triggered @State, .animation(.easeOut.delay(min(index,8)*0.05)); skip when reduce-motion.

### lib/widgets/shared/fk_shimmer.dart (FkShimmer)

_Sweeping highlight gradient over skeleton/child._

Props: child, enabled=true. controller duration shimmer 1400ms; repeat() started in didChangeDependencies only if enabled && !reduceMotion (NOT initState — so test/reduce-motion never hangs). Build: reduceMotion||!enabled -> plain child. Else AnimatedBuilder ShaderMask srcATop with LinearGradient topLeft->bottomRight colors [surfaceContainerHigh, surfaceBright, surfaceContainerHigh] stops [0.1,0.5,0.9] translated horizontally dx=width*(value*2-1). Swift: a moving LinearGradient mask via .mask + TimelineView/repeatForever animation; disable on reduce-motion.

### lib/widgets/shared/fk_check_circle.dart (FkCheckCircle)

_Round checkbox: filled+check when checked, press-scale, selection haptic._

Props: checked, onTap, size=28. Wrapped in FkAnimatedPressable(selection). AnimatedContainer (duration normal 180ms, zero if reduceMotion) size×size circle: checked-> fill primary, border primary w2, child Icon(check_rounded size*0.6 color onPrimary); unchecked-> transparent fill, border outline w2, no child. Swift: Circle().fill/.strokeBorder + checkmark Image, .animation.

### lib/widgets/shared/fk_card.dart (FkCard)

_FK primary card: radius 20, white, 2-layer soft shadow; optional tap + gradient._

Props: child, padding=EdgeInsets.all(lg 16), onTap?, backgroundColor?, borderRadius=xl 20, gradient? (mutually exclusive with bg — gradient wins, bg ignored), shadows?(default AppShadows.card). Container decoration: color = gradient==null ? (bg ?? surfaceContainerLowest) : null; boxShadow shadows. onTap!=null -> wrap FkAnimatedPressable. Swift: a reusable Card view = RoundedRectangle background (fill or gradient) + .shadow x2; tappable variant uses the pressable style.

### lib/widgets/shared/fk_pill.dart (FkPill + FkStatus + kFkStatusStyles + FreshnessStatusX)

_URGENCY/STATUS SINGLE SOURCE OF TRUTH + small capsule label._

enum FkStatus {fresh, soon, urgent, expired, low}. class FkStatusStyle {Color bg; Color fg; String label}. kFkStatusStyles map: fresh=(primarySoft E5ECFA, primaryContainer 3F60B5, '新鲜'), soon=(fkWarnSoft FFF3D6, onSecondaryContainer 9B7A2A, '即将过期'), urgent=(fkDangerSoft FBE0D7, onTertiaryContainer B5523A, '快过期'), expired=(fkDanger E76F51, white, '已过期'), low=(fkDangerSoft FBE0D7, onTertiaryContainer B5523A, '库存不足'). extension FreshnessStatusX on FreshnessState: fkStatus mapping fresh->fresh, expiringSoon->soon, urgent->urgent, expired->expired; statusStyle = kFkStatusStyles[fkStatus]!. (FreshnessState enum = {fresh, expiringSoon, urgent, expired}; NOTE: domain has 4 states, FkStatus adds `low` for shopping/low-stock.) FkPill widget props: label, leading?, backgroundColor?(default surfaceContainer F0EBE3), foregroundColor?(default onSurfaceVariant), sm=false, onTap?, border?. Padding h(sm?8:10) v(sm?3:5), radius pill. Text Manrope (sm?11:12)/w600 letterSpacing -0.1 height1.2. leading Icon size sm?11:12 colored fg, gap xs. factory FkPill.status(FkStatus, sm) uses style bg/fg/label. Swift: an enum FreshnessStatus with style tuple; a Pill/Capsule view; map domain FreshnessState->status.

### lib/widgets/shared/fk_status_badge.dart (FkStatusBadge)

_Thin alias: status badge = FkPill.status._

Props: status (FkStatus), sm=false. Returns FkPill.status(status, sm:sm). Swift: trivial wrapper or just use the Pill.

### lib/widgets/shared/fk_icon_button.dart (FkIconButton)

_Circular single-icon button with 3 variants._

Props: child, onTap?, size=36, backgroundColor?, foregroundColor?, primary=false, onImage=false, shadows?. bg: primary->primary; onImage->white@0.95; else backgroundColor??white. fg: primary->white; else foregroundColor??onSurface. shadow: primary->AppShadows.strong, else default [subtleShadow blur3 offset(0,1)]. Circle Container size×size; IconTheme color fg, icon size primary?26:18. onTap!=null wraps FkAnimatedPressable. Used by FkTopBar back button and bottom nav. Swift: a circular Button with conditional fill/foreground/shadow.

### lib/widgets/shared/fk_hero_header.dart (FkHeroHeader)

_Gradient hero block with rounded bottom + decorative blobs._

Props: child, gradient=[primary, primaryContainer], bottomRadius=hero 28, padding=fromLTRB(xl 20, xxl 24, xl 20, 80), showDecorations=true, begin=topLeft, end=bottomRight. ClipRRect only-bottom corners; Container LinearGradient; Stack with two white circle blobs when showDecorations: _Blob(180, white@0.07) at right:-40 top:-30, _Blob(60, white@0.09) at right:30 top:60; then padded child. Swift: ZStack with LinearGradient bg .clipShape(rounded-bottom corners via UnevenRoundedRectangle), Circle blobs positioned via .offset, content overlay.

### lib/widgets/shared/fk_dashed_border.dart (FkDashedBorder)

_Dashed rounded-rect border via CustomPaint (for 'missing ingredient' chips, 'clear completed' button)._

Props: child, color, strokeWidth=1, radius=12, dashLength=4, gapLength=3, fillColor?. CustomPaint _DashedRRectPainter: insets stroke/2, RRect radius clamped to shortestSide/2; optional fill draw; stroke paint round cap; iterate path.computeMetrics extracting dashLength segments stepping dashLength+gapLength. radius=pill renders capsule/circle. Swift: RoundedRectangle().strokeBorder(style: StrokeStyle(lineWidth, dash:[4,3], lineCap:.round)); optional fill behind.

### lib/widgets/shared/fk_empty_state.dart (FkEmptyState)

_Unified empty state: 64 circle soft icon + title + subtitle._

Props: icon (IconData), title, subtitle. Padding symmetric(h xl 20, v 60). Centered Column min: 64×64 circle primarySoft bg with Icon(icon size32 primary); gap lg; Text title JakartaSans 16/w700 onSurface center; gap xs; Text subtitle Manrope 12 onSurfaceVariant center. No built-in entrance (caller wraps FkEntrance). Swift: VStack with Circle icon badge + two Texts.

### lib/widgets/shared/fk_image_placeholder.dart (FkImagePlaceholder)

_Diagonal-stripe image placeholder with shimmer + centered mono label._

Props: width?, height=120, label?, tint=surfaceContainer, borderRadius=chip 14. Wrapped in FkShimmer + ClipRRect. CustomPaint _StripePainter: base fill tint, rotate 45deg, draw 8px-wide black@0.02 stripes every 16px across width+height. Optional centered label JetBrains Mono 10 outline color letterSpacing0.4. Swift: Canvas-drawn diagonal stripes or a tiling pattern image with .mask; shimmer overlay.

### lib/widgets/shared/fk_skeleton.dart (FkSkeletonBox + FkSkeletonLine)

_Skeleton building blocks for loading states (pair with FkShimmer)._

FkSkeletonBox props width?, height=16, radius?(default sm 8): Container surfaceContainerHigh color rounded. FkSkeletonLine props width?, height=12: delegates to FkSkeletonBox radius xs 4. Swift: RoundedRectangle().fill(surfaceContainerHigh) with fixed/flexible frame.

### lib/widgets/shared/fk_skeleton_card.dart (FkRecipeSkeletonCard)

_Recipe-card-shaped skeleton (130h, left 120 square + lines)._

FkShimmer > Container 130h surfaceContainerLowest radius xl, Row: FkSkeletonBox(120×130) + Expanded padded Column spaceBetween: top Column [FkSkeletonLine(140), gap sm, FkSkeletonLine(90)] + bottom FkSkeletonLine(infinity). Swift: HStack mirroring RecipeCard layout with skeleton blocks + shimmer.

### lib/widgets/shared/fk_section_head.dart (FkSectionHead)

_Section header: title + optional count + right action/trailing._

Props: title, count?, actionLabel?, onAction?, trailing?, padding=fromLTRB(18,18,18,10). Row baseline-aligned: Text title JakartaSans 16/w700 letterSpacing-0.2 onSurface; if count Text Manrope 13 onSurfaceVariant w500 after gap sm; Spacer; if trailing show it else if actionLabel GestureDetector Row[Text Manrope 13/w600 primary + Icon chevron_right 16 primary]. Swift: HStack with title Text, optional count, Spacer, action button.

### lib/widgets/shared/fk_top_bar.dart (FkTopBar)

_Large-title top bar with optional subtitle + back/actions._

Props: title, subtitle?, onBack?, leading?, actions=[], dense=false, backgroundColor?. left = leading ?? (onBack? FkIconButton with arrow_back_ios_new_rounded size18). Container padding fromLTRB(18, dense?8:14, 18, dense?8:14). Row crossStart: left (padded top dense?0:xs) + gap10; Expanded Column: Text title JakartaSans (dense?18:22)/w700 letterSpacing-0.3 onSurface height1.2; if subtitle gap2 + Text Manrope 13 onSurfaceVariant height1.3. Actions row (gap sm between). Caller handles SafeArea. Swift: a custom nav header view (since this replaces the platform AppBar for FK screens); use .toolbar or a manual header HStack.

### lib/widgets/shared/freshness_meter.dart (GradientFreshnessMeter)

_Horizontal gradient freshness bar with end labels._

Props: percent (0..1). Column: Row spaceBetween two labels '最佳新鲜'/'即将到期' (11/w700 letterSpacing0.5 onSurfaceVariant@0.7). gap sm. ClipRRect pill, 8h Stack: track surfaceContainerHighest, FractionallySizedBox widthFactor percent.clamp with LinearGradient [primary, tertiaryFixedDim, secondaryContainer]. Swift: GeometryReader bar with gradient fill width=percent*total.

### lib/widgets/shared/pill_chip.dart (PillChip)

_General configurable pill chip with optional icon/selected/tap/border._

Props: label, icon?, selected=false, onTap?, padding=symmetric(h md 12,v sm 8), iconSize=16, iconForegroundColor?, iconLabelGap=6, fontSize=13, fontWeight=w600, backgroundColor?, foregroundColor?, selectedBackgroundColor?, selectedForegroundColor?, borderColor?. Color resolution: defaultBg = selected ? (selectedBg ?? primary) : (bg ?? surfaceContainerLow); defaultFg = selected ? (selectedFg ?? onPrimary) : (fg ?? onSurfaceVariant); iconColor = iconForegroundColor ?? defaultFg. Container radius pill, optional Border w1.5. Row icon+gap+Text Manrope. onTap wraps FkAnimatedPressable. Used by category/cooking/unit selectors and dashboard tags. Swift: a versatile Chip view with selection styling.

### lib/widgets/shared/cat_icon.dart (CatIcon + kFkCategoryIds)

_9 hand-drawn line SVG icons for food categories (36×36 viewBox, strokeWidth 1.8)._

Props: category, size=28, color=onSurface, strokeWidth=1.8. Looks up _kCatSvg[category] ?? veg; replaces {stroke}/{fill}/{sw} placeholders with hex(color)/strokeWidth; renders via flutter_svg SvgPicture.string. _hex converts Color rgb to #rrggbb. kFkCategoryIds = [veg,fruit,meat,sea,dairy,drink,sauce,grain,snack]. Full SVG path strings are embedded (cartoon veg/fruit/meat/sea/dairy/drink/sauce/grain/snack). Swift: ship 9 SVG/PDF assets or vector path data; tint via .foregroundStyle; replace flutter_svg with SVG asset or Shape paths. SVG path source-of-truth is in this file.

### lib/widgets/shared/category_icon.dart (CategoryIconAvatar + mapping helpers)

_Category avatar (tinted rounded box + CatIcon) + 5-class<->9-id mappings; legacy icon helpers._

fkCategoryIdFor(category?) maps FoodCategories coarse 5 classes -> fine id: dairyAndEggs->dairy, freshProduce->veg, meatAndSeafood->meat, herbsAndSpices->sauce, _->grain. foodCategoryForFkId(catId) reverse: dairy->dairyAndEggs, veg|fruit->freshProduce, meat|sea->meatAndSeafood, sauce->herbsAndSpices, _->other. categoryIconFor(category?) legacy IconData fallback (egg_outlined/eco_outlined/set_meal_outlined/spa_outlined/restaurant_outlined). CategoryIconAvatar props: category?, size, iconSize, muted=false, borderRadius=12. catId = FkCategoryPalette.all.containsKey(category) ? category : fkCategoryIdFor(category). palette = of(catId). tint = muted? surfaceContainerHigh : palette.tint; ink = muted? outline : palette.ink. Container size box radius tint bg + centered CatIcon. Swift: avatar view = rounded rect tint bg + category vector ink; replicate both mappings as functions.

### lib/widgets/shared/zone_icon.dart (ZoneIcon + kFkZoneIds + kFkZoneNames)

_5 storage-zone line SVG icons (24×24, strokeWidth 1.7)._

Props: zone, size=16, color=outline, strokeWidth=1.7. _kZoneSvg keys: fridge, freezer, door, box, pantry (fallback fridge); same {stroke}/{fill}/{sw} substitution + SvgPicture.string. kFkZoneIds=[fridge,freezer,door,box,pantry]. kFkZoneNames: fridge->冷藏区, freezer->冷冻区, door->门架, box->保鲜盒, pantry->常温. NOTE: domain IconType enum only has {fridge,freezer,pantry}; door/box are design-only zones. Swift: 5 vector assets + id->name map.

### lib/widgets/shared/fk_nav_icon.dart (FkNavIcon + kFkNavIconIds)

_5 bottom-nav tab line SVG icons (24×24, strokeWidth 1.7)._

Props: icon, size=22, color=outline, strokeWidth=1.7. _kNavSvg keys: home, fridge, recipes, shopping, add (fallback home). fridge path == ZoneIcon fridge. kFkNavIconIds=[home,fridge,recipes,shopping,add]. Swift: 5 vector assets used by the TabView/custom tab bar.

### lib/widgets/shared/recipe_cover_fallback.dart (RecipeCoverFallback)

_Recipe cover placeholder colored by DISH category (not ingredient category)._

Props: category? (Recipe.category like 荤菜/素菜...), iconSize=32. _visualFor switch on Chinese dish category -> (FkCatColors, Material IconData): 荤菜->(meat, kebab_dining_rounded), 素菜->(veg, eco_rounded), 主食->(grain, rice_bowl_rounded), 水产->(sea, set_meal_rounded), 早餐->(snack, bakery_dining_rounded), 饮品->(drink, local_cafe_rounded), 汤羹->(sea, ramen_dining_rounded), 甜品->(fruit, cake_rounded), 半成品->(sauce, blender_rounded), 酱料->(sauce, water_drop_rounded), _->(grain, restaurant_rounded). DecoratedBox LinearGradient [tint, lerp(tint,white,0.45)] + centered Icon ink. Swift: dish->(style,SFSymbol) map; gradient fill + symbol.

### lib/widgets/shared/recipe_image.dart (RecipeImage)

_Smart image loader: data-URI/base64, asset, or cached remote URL; decode-size capped to render box to avoid white-flash on tab switch._

Props: imageSource?, fallback (Widget), fit=cover, width?, height?, semanticLabel?, cacheManager?(injection for tests). StatefulWidget caches decoded base64 bytes; resets on imageSource change. Empty/null source -> fallback. LayoutBuilder computes box w/h from explicit width/height or finite constraints; cacheWidth = (boxW*dpr).round (else cacheHeight). data:image/...;base64, -> Image.memory(bytes, cacheWidth/Height, errorBuilder->fallback). assets/ prefix -> AssetImage; else CachedNetworkImageProvider(source). ResizeImage.resizeIfNeeded wraps provider. Standard Image (NOT CachedNetworkImage widget) with gaplessPlayback true; frameBuilder returns child if wasSynchronouslyLoaded||frame!=null else fallback; errorBuilder->fallback. Rationale: cap decode to render box so ImageCache (default 100MB) doesn't evict covers -> no async first-frame flash. Swift: AsyncImage/Kingfisher/Nuke with downsampling to target size + disk cache; base64 -> UIImage(data:); 'assets/' -> bundle image; show fallback view on failure.

### lib/widgets/shared/ai_busy_overlay.dart (AiBusyOverlay)

_Modal busy overlay during AI URL parse._

Props: message='正在抓取网页并解析…'. AbsorbPointer over ColoredBox black@0.25, centered Material surface elevation4 radius lg, padded Column: 28×28 CircularProgressIndicator(2.5) + gap md + Text bodyMedium onSurface w600. Swift: ZStack dim overlay + ProgressView card; .allowsHitTesting(false) on content.

### lib/widgets/shared/ai_draft_field.dart (AiDraftFieldChip<T>)

_AI/user-sourced editable field chip with left accent bar + bottom-sheet editor._

Generic<T>. Props: label, field (DraftField<T> {value, source}), onChanged(DraftField<T>), formatter?(T->String), editorBuilder?(initial,save->Widget). isAi = source==DraftSource.ai (enum {ai,user,hybrid}). accent = isAi? aiAccent(primary) : aiAccentMuted(outline). display = formatter(value) ?? value.toString. InkWell -> _openEditor (showModalBottomSheet with viewInsets-aware padding, builds editorBuilder(value, save) where save calls onChanged(field.editedTo(next)) + pop). Container accent@0.06 bg, left Border accent w3, radius sm; Column: Row[label 11/w700 accent + Spacer + if isAi 'AI 填'] + value Text 14/w600. Swift: a chip with leading accent bar + sheet editor; DraftField is a model elsewhere.

### lib/widgets/shared/expiry_range_picker.dart (showExpiryRangePicker + ExpiryRangePickerDialog)

_Full-screen custom date-range picker (start/end tabs + Cupertino wheel) for shelf-life._

showExpiryRangePicker(context, initialDateRange, firstDate, lastDate, currentDate) -> showDialog<DateTimeRange> useSafeArea:false barrierColor modalBarrier, Localizations.override zh_CN. Dialog stateful: _startDate/_endDate (clamped to firstDate..lastDate, end>=start), _editingStartDate bool. Layout: Material surface SafeArea Column: topbar (close X + '确定' TextButton primary 16/w800 -> pop DateTimeRange), header '选择保质期范围' 16/w800 onSurfaceVariant, two-tab segmented control (起始日期/结束日期 each showing date YYYY年M月D日, selected tab elevated white card), Expanded CupertinoDatePicker mode date dateOrder ymd minYear/maxYear from first/last, onDateTimeChanged updates active date with clamp+cross-adjust. Custom overlay style. Keys: expiry-range-picker, expiry-start/end-date-tab, expiry-date-wheel. Swift: a custom sheet with segmented Picker + DatePicker(.wheel); clamp logic identical.

### lib/widgets/recipe_card.dart (RecipeCard + RecipeCardLayout)

_Recipe card in horizontal (120 left cover) or banner (16:9 top) layout with match progress, tags, 临期 badge, favorite heart._

enum RecipeCardLayout {horizontal, banner}. Props: recipe, matchedCount?, subtitle?, ingredientLabel?, trailing?, onTap?, useExpiring=false, isFavorite=false, onToggleFavorite?, expiringUseCount?, heroTag?, layout=horizontal. Semantics(button=onTap!=null, label=recipe.name) > FkCard(padding zero, onTap). Horizontal: SizedBox 130h Row [_Cover 120w, Expanded padded _RecipeMeta(expand:true), ?trailing]. Banner: Column [_BannerCover, padded _RecipeMeta(expand:false)]. _RecipeMeta: missing=(total-matched).clamp; ratio=matched/total; progressColor = ratio>=1 ? primary : ratio>=0.7 ? primaryLight : fkWarn. nameBlock: name JakartaSans 15/w700 ellipsis + Row[schedule icon 11 + '{cookingMinutes} 分钟' + '· {difficultyLabel}'] Manrope 11 onSurfaceVariant. progressBlock: Row['食材匹配 m/t' or ingredientLabel, 11/w700 primary + Spacer + if missing '缺 N 件' 11/w600 fkDanger] + 4h track surfaceContainer with progressColor fill widthFactor ratio + if tags first 2 FkPill(sm) in horizontal ListView 22h. _Cover: ClipRRect left corners xl, _CoverImage(fallbackIconSize 32), optional Hero(heroTag). Stack: cover + if useExpiring _ExpiringBadge top8 left8 + if onToggleFavorite _FavoriteHeart top6 right6. _BannerCover: top corners xl AspectRatio 16/9, badge top10/left10, heart top8/right8. _CoverImage: blurred same-image fill (ImageFilter.blur 18) under contain full image + dark scrim 0x14000000 + primarySoft base; null source->fallback. _FavoriteHeart: key recipe_card_favorite_{id}, white@0.92 circle AppShadows.card, Icon favorite_rounded/favorite_border 15, fkDanger when fav. _ExpiringBadge: fkWarn pill, fire icon + label '临期' or '临期 · N' when count>=2. Swift: HStack/VStack card; progress bar; overlays for badge/heart; blurred backdrop image.

### lib/widgets/inventory/ingredient_card.dart (IngredientCard + freshnessBadgeColors)

_Inventory grid card (2-col): CatIcon avatar + name + qty/zone + 4px freshness progress + status pill + inline buy-again._

freshnessBadgeColors(FreshnessState) -> (bg, text) from state.statusStyle. IngredientCard props: ingredient, onBuyAgain?, onTap?, heroTag?. state, isFresh=fresh, isExpired=expired, catId=fkCategoryIdFor(category), palette=of(catId), progress=freshnessPercent.clamp, progressColor = isExpired ? style.bg : style.fg. Container white radius lg AppShadows.soft pad md, Column: Row[_buildAvatar(48 box radius md palette.tint + CatIcon 30 palette.ink, optional Hero) + Spacer + ?statusBadge]; gap10; name JakartaSans 14/w700 onSurface@(isExpired?0.6:1) ellipsis; gap2; Row[qty+unit + ' · ' + ZoneIcon(_zoneId(storage) 12) + storageLabelFor] Manrope 11 onSurfaceVariant; gap10; 4h track surfaceContainer with TweenAnimationBuilder animated width (begin0 end progress.clamp(0.05,1), slow 250ms, zero if reduceMotion) progressColor fill; if onBuyAgain && !isFresh: FkAnimatedPressable '加购' button primarySoft bg radius10 primaryContainer text 11/w700. _statusBadgeFor: fresh->null else FkPill(expiryLabel ?? defaultLabel, .toUpperCase, bg/fg from colors, sm). _zoneId maps storage enum name fridge/freezer/pantry (default fridge). Swift: grid card view; animated progress bar; status pill from FreshnessStatus.

### lib/widgets/dashboard/expiring_fallback_card.dart (ExpiringFallbackCard)

_Dashboard '用临期食材' recipe suggestion card (Riverpod-driven)._

ConsumerWidget watches expiringFallbackRecipeProvider; null->SizedBox.shrink. FkCard(pad zero, onTap pushRouteOnce -> RecipeDetailScreen(recipe, useExpiring:true)). SizedBox 130h Row: 96w cover ClipRRect left corners, RecipeImage(recipe.imageUrl) fallback fkWarnSoft bg + local_fire_department fkWarn 36; Expanded padded Column spaceBetween: top['用临期食材' 11/w600 fkWarn letterSpacing1 + recipe.name 16/w700 ellipsis]; bottom['可用 N 件临期食材' 12 outline + Wrap first 3 covered names as PillChip fkWarnSoft/onSecondaryContainer]. Swift: card driven by a derived suggestion; reuse PillChip styling.

### lib/widgets/dashboard/low_stock_card.dart (LowStockCard + runBulkLowStockAdd)

_Dashboard low-stock list card + bulk add-to-shopping action._

ConsumerWidget watches lowStockItemsProvider (List<FrequentItem>); empty->shrink. FkCard pad lg Column: Row[warning_amber fkWarn 20 + '库存不足 (N 项)' 16/w700]; first 4 _LowStockRow; if >4 '+ 还有 X 项' 12 outline; FilledButton.icon key low_stock_bulk_add_cta '全部加入购物清单 (N)' -> runBulkLowStockAdd. _LowStockRow: CatIcon(fkCategoryIdFor(category) 20) + name w600 + '已买 N 次' 12 outline. runBulkLowStockAdd(context,ref,items): showAppConfirmDialog listing '{name} (已买 {count} 次)', on confirm loop shopping.addFromSuggestion counting successes, snackbar '已添加 N 项' or '所选项目已在购物清单中'. Swift: list card + confirm dialog + batched shopping adds + toast.

### lib/widgets/dashboard/waste_insights_card.dart (WasteInsightsCard)

_Dashboard entry card to waste-reduction stats (hidden when empty)._

ConsumerWidget watches foodLogMonthStatsProvider; stats.isEmpty->shrink. subtitle = wasted==0 ? '本月用掉 {consumed} 样 · 零浪费 👏' : '本月用掉 {consumed} · 浪费 {wasted}'. FkCard key dash-waste-insights onTap pushRouteOnce->WasteInsightsScreen. Row: 44 box primarySoft radius chip eco_outlined primary 24 + Expanded Column['减废成效' 14/w700 onSurface + subtitle 12 onSurfaceVariant ellipsis] + if rescued>0 _RescuedBadge('抢救 N' fkWarnSoft/onSecondaryContainer chip) + chevron_right onSurfaceVariant 22. Swift: nav card with leading icon badge + subtitle + optional badge + chevron.

### lib/widgets/dashboard/weekly_plan_card.dart (WeeklyPlanCard)

_Dashboard entry card to weekly meal plan (always visible)._

ConsumerWidget watches mealPlanWeekSummaryProvider; hasPlan = upcoming>0. subtitle: !hasPlan '还没安排 — 点这里规划这周吃什么'; today>0 '本周已排 {upcoming} 顿 · 今天 {today} 顿'; else '本周已排 {upcoming} 顿'. FkCard key dash-weekly-plan onTap->MealPlanScreen. Row: 44 box primarySoft radius chip calendar_month_outlined primary 24 + Expanded Column['本周计划' 14/w700 + subtitle 12 onSurfaceVariant ellipsis] + if missing>0 _MissingBadge('还缺 N 样' fkWarnSoft/onSecondaryContainer) + chevron_right 22. Swift: same nav-card pattern as waste card.

### lib/widgets/common/bottom_nav_bar.dart (BottomNavBar)

_5-tab frosted bottom nav with center primary FAB (Riverpod navigation)._

ConsumerWidget watches navigationProvider (currentIndex). _items: (home,首页)(fridge,食材)(add,'')(recipes,菜谱)(shopping,清单); index FkTab.add is center. ClipRRect top corners xxl 24, BackdropFilter blur 14/14, Container surface@0.92 + top hair border 0.5, SafeArea(top:false) padded Row spaceAround crossEnd. Tab==add -> _PrimaryFab(52×52 = profileAvatar-xs, primary circle AppShadows.strong, FkNavIcon add size iconMd+6 onPrimary strokeWidth2, light haptic, Semantics '添加食材'); else _TabButton(FkNavIcon 22 + label labelSmall, color primary if active else outline, selection haptic, Semantics selected). Calls ref.navigateToTab(index). Swift: custom tab bar (TabView or manual) with .ultraThinMaterial background + center floating button.

### lib/widgets/common/top_app_bar.dart (TopAppBar + kTopAppBarHeight)

_Dashboard header (app icon + title + settings/search) over hero gradient._

kTopAppBarHeight=64. ConsumerWidget watches householdSessionControllerProvider.select(pendingInvitePreviews.isNotEmpty)->hasInvite. SizedBox 64h padded h xxl, Row spaceBetween: left[app_icon.png 40×40 ClipRRect md (errorBuilder Icon error) + gap md + '食材管家' JakartaSans 20/w700 white]; right[Stack settings IconButton white (tooltip varies if hasInvite) + if hasInvite 8×8 fkAlert dot badge key settings_invite_badge at right8/top10; search IconButton white -> searchActiveProvider=true]. White text because it sits on hero gradient. Swift: header HStack; settings/search buttons; invite badge dot.

### lib/widgets/common/search_overlay.dart (SearchOverlay)

_Full-screen blurred search overlay: field + history panel + grouped results (inventory/shopping/food encyclopedia)._

ConsumerStatefulWidget. Debounce 150ms; _maxVisibleResultsPerSection=5. PopScope canPop:false -> _close on back. Blurred barrier (blur 2/2, onSurface@0.4) tap closes. _SearchField: white rounded lg shadow, TextField autofocus search action, search prefix primary, close suffix. _close: unfocus, add term to searchHistoryProvider, clear, searchProvider='', searchActiveProvider=false. Keyword empty -> _SearchHistoryPanel (watches searchHistoryProvider; '最近搜索' header + clear; ListView history rows with history icon, remove X, onTap select). Else _SearchResultsPanel (maxHeight 55% screen) building _SearchResultsList from filteredInventoryProvider/filteredShoppingProvider/searchFoodDetailsProvider. Rows modeled as _SearchResultRow with kinds {header,divider,inventory,shopping,foodDetails,loading,error,hint} each with fixed itemExtent (header44/inventory64/shopping64/foodDetails72/loading56/error64/hint40/divider1); content rows wrapped FkEntrance with compact stagger index. Section headers show icon+title+count pill (primaryFixed). _InventoryResultTile: 8px status dot (expired->bg coral else fg), name+'{qty} {unit} · {category}', trailing expiryLabel colored. _ShoppingResultTile: check icon, strikethrough when checked, '{detail} · {category}'. _FoodDetailsResultTile: 44 RecipeImage w/ CategoryIconAvatar fallback + foodDetailsSummary. Loading/error/empty tiles. _ShowMoreHint italic '还有 N 个X结果'. Swift: a search sheet/overlay with sectioned List + debounced query + history.

### lib/widgets/common/swipe_reveal_delete_action.dart (SwipeRevealDeleteAction)

_Custom swipe-to-reveal delete (slide row left to expose red delete button)._

Props: child, onDelete, deleteButtonKey?, actionExtent=84, borderRadius=md. State: _dragOffset (clamped -actionExtent..0), _isDragging, _isAnimatingClosed. _isOpen = offset<=-actionExtent+0.5. Drag end: shouldOpen if velocity<-350 or |offset|>40% extent; shouldClose if velocity>350; closing if shouldClose||!shouldOpen -> offset 0 else -extent. Cancel always closes. ClipRRect Stack: red delete panel (Material error, InkWell onDelete, delete_outline + '删除' onError, IgnorePointer until open, Semantics button '删除', key delete_panel) behind AnimatedContainer (zero duration while dragging else normal 180ms, translateX offset, onEnd resets _isAnimatingClosed) wrapping GestureDetector horizontal drag + child. Swift: custom swipeActions or DragGesture-driven offset with trailing delete; SwiftUI .swipeActions is the natural replacement.

### lib/widgets/common/sync_status_banner.dart (SyncStatusBanner)

_Thin online/offline + pending-sync banner._

ConsumerWidget watches syncStatusProvider (status.showBanner, online, pendingCount). label when showBanner: online -> '同步中 · N 条待同步'; offline & pending>0 -> '离线 · N 条待同步'; else '离线'. AnimatedSize (normal 180ms or zero if reduce-motion) topCenter. When showBanner: Material color online?primary:onSurfaceVariant, SafeArea(bottom:false) padded Row[Icon sync/cloud_off 16 onPrimary + label onPrimary 12] else SizedBox.shrink. Swift: a collapsible banner bound to sync state actor; animate height.

### lib/widgets/household/household_section.dart (HouseholdSection + sub-rows/dialogs)

_Family-sharing settings section: household name/switcher, members, pending/incoming invites, invite actions, dissolve/leave._

Stateless props (many callbacks): householdName, members(List<HouseholdMember>{userId,email,role}), onInvite?, onInviteLink?(Future), onInviteEmail?(Future(email)), isOwner=false, currentUserId='', onRemoveMember?(Future(userId)), ownerPendingInvites(List<OwnerPendingInvite>{id,email}), onRevokeInvite?(Future(inviteId)), onDissolveHousehold?(Future), households(List<Household>{id,name}), selectedHouseholdId, onSwitchHousehold?(String), onEditName?(Future(newName)), onLeaveHousehold?(Future), incomingInvites(List<HouseholdInvitePreview>{inviteId,householdName,ownerEmail,inventoryCount,memberCount}), onAcceptInvite?(Future(inviteId)). canInvite=isOwner && (any invite cb). FkSectionHead '家庭共享' count members.length; FkCard: header Row [36 circle primarySoft home_rounded primaryContainer + (households>1 && onSwitchHousehold? DropdownButton of household names : Text name titleMedium w700) + if owner&&onEditName edit IconButton -> _EditNameDialog]. Incoming invites block (title '收到的邀请' + _IncomingInviteRow each: mail icon + householdName + '来自 {ownerEmail} · {inventoryCount} 项库存 · {memberCount} 名成员' + FilledButton '接受'). Members: empty->'登录后会显示家庭成员' else _buildMemberRow (Dismissible endToStart with confirm '移除成员' when owner&&not-self&&role!=owner&&onRemoveMember; _MemberRow account icon + email + FkPill role '拥有者'/'成员'). Owner pending invites block ('待处理邀请' + _PendingInviteRow: target = email or '扫码/链接邀请' + '待接受' + revoke X fkDanger). _InviteActions: FilledButton.icon qr_code_2 '扫码/链接邀请' + OutlinedButton.icon mail '邮箱定向邀请' -> _InviteMemberDialog. Dissolve (owner): TextButton.icon delete_forever fkDanger '解散家庭'. Leave (non-owner): TextButton.icon logout fkDanger '退出家庭' with confirm. _InviteMemberDialog/_EditNameDialog: stateful TextField + submit with loading/error. Swift: a settings section view + sheets/alerts; dropdown -> Menu/Picker; swipe-to-remove via .swipeActions.

### lib/widgets/settings/invite_result_sheet.dart (InviteResultSheet)

_Bottom sheet showing generated invite link as QR + copy/share actions._

Props: inviteUrl, invitedEmail=''. static show(context, inviteUrl, invitedEmail) -> showModalBottomSheet isScrollControlled surface rounded top xl. Body SafeArea SingleChildScrollView pad xl Column: drag handle 40×4 outlineVariant; '邀请链接已创建' titleLarge w700; subtitle (invitedEmail or '分享链接或二维码，家人登录后即可加入') bodyMedium onSurfaceVariant; RepaintBoundary(key _qrBoundaryKey) white card border outlineVariant QrImageView(inviteUrl, version auto, size200, white bg); selectable URL box surfaceContainer; FilledButton.icon copy_rounded '复制链接' (Clipboard + pop + fkToast '邀请链接已复制'); OutlinedButton.icon share_rounded '分享链接' (SharePlus text); OutlinedButton.icon qr_code_2 '分享二维码' (render QR boundary to PNG pixelRatio3, share XFile). Swift: a sheet with QR (CIQRCodeGenerator or a SwiftUI QR lib), copy via UIPasteboard, ShareLink for link + rendered image (ImageRenderer).

### lib/widgets/shopping/quick_add_field.dart (QuickAddField)

_Shopping quick-add text field (add item by name)._

ConsumerStatefulWidget props: focusNode?. Outer Container surfaceContainerLow radius md > inner surfaceContainerHigh radius sm > TextField: hint '添加食材到清单...', add_circle primary prefix, send IconButton suffix, no border, on submit/send _submit. _submit: trim, shopping.addFromSuggestion(name) (catch -> snackbar '添加失败，请重试'), clear+unfocus, snackbar added?'已将「name」加入购物清单'(primary):'「name」已在购物清单中'(tertiary). Swift: a TextField with leading/trailing icons calling the shopping store; toasts.

### lib/widgets/recipe_form/ai_collapsible_banner.dart (AiCollapsibleBanner)

_Collapsible AI-import banner (paste URL -> parse)._

StatefulWidget (public state expand()). Props: urlController, onParse, initiallyExpanded=false, isLoading=false. AnimatedSize (slow 250ms, decelerate). Collapsed: InkWell -> expand; primaryFixed@0.5 bg border primaryFixed radius md; '✨ 粘贴链接，AI 自动填表' bodyMedium primary w600 + '展开' primary pill. Expanded: aiGradient (start->end) radius lg; '✨ 用 AI 一键导入' labelLarge onPrimary; TextField key recipe_url_input url keyboard, normalizePastedRecipeUrl on change, white fill, hint '粘贴食谱链接 (懒饭 / 下厨房…)', readOnly while loading; FilledButton key recipe_url_parse '解析并填入' (spinner+'解析中…' when loading) -> onParse. Swift: DisclosureGroup-like collapsible with gradient expanded state + URL field + parse button.

### lib/widgets/recipe_form/ai_draft_review_banner.dart (AiDraftReviewBanner)

_Banner shown after AI fills a recipe draft (regenerate/discard)._

Props: sourceUrl?, onRegenerate, onDiscard, onLoading=false. Container key ai_draft_review_banner primaryFixed@0.35 border primaryFixed radius md pad lg. Column: '✨ AI 草稿已填入，请核对下方字段' titleSmall primary w700; if sourceUrl '来源: {url}' bodySmall ellipsis 2 lines; Row 44h two OutlinedButtons keys ai_draft_review_regenerate '重新生成' / ai_draft_review_discard '丢弃草稿' (disabled while loading). Swift: an info banner with two outlined buttons.

### lib/widgets/recipe_form/cooking_time_row.dart (CookingTimeRow)

_Cooking-time selector: preset PillChips + custom numeric input._

StatefulWidget props: controller, onChanged(int?), errorText?. Listens to controller for setState. ListView horizontal of RecipePresets.cookingMinutes as PillChip (last shows '{n}+'), selected when current==minutes, selectedBg primary/selectedFg onPrimary, onTap sets controller.text + onChanged. Then Row '或自定义' + 72w TextField digitsOnly center + '分钟', onChanged int.tryParse. Swift: horizontal chip scroller + numeric TextField bound to a shared value.

### lib/widgets/recipe_form/difficulty_stars.dart (DifficultyStars)

_5-star difficulty selector with label._

Props: value(int 1..5), onChanged(int). _labels = [简单,较易,普通,进阶,专业]. Row of 5 GestureDetector star_rounded 32 colored secondaryContainer if i<value else surfaceContainerHigh, onTap onChanged(i+1); then label pill urgentAttentionBackground radius pill labelMedium onSurface w700. Swift: HStack of tappable star Images + label capsule.

### lib/widgets/recipe_form/recipe_category_chips.dart (RecipeCategoryChips)

_Wrapping recipe-category chip selector + custom-category dialog._

Props: selected, onChanged(String). _customSentinel='+ 其他'. categories = RecipePresets.categories + (selected if not in list) + sentinel. Wrap spacing/runSpacing sm of PillChip selected==selected; tapping sentinel opens _CustomCategoryDialog (TextField '例如：日料', returns trimmed). Swift: a wrapping chip layout (LazyVGrid/FlowLayout) + alert with text field.

### lib/widgets/recipe_form/recipe_form_card.dart (RecipeFormCard)

_Bordered form-section card with icon header + optional count + error state._

Props: icon, title, child, countLabel?, iconBackgroundColor?(default primaryFixed), iconForegroundColor?(default primary), hasError=false. Container surfaceContainerLowest radius lg border (error red w1.5 else outlineVariant w1) pad lg. Row: 30 box iconBg radius sm Icon iconFg 18 + title titleMedium w800 + optional countLabel pill surfaceContainer. Then gap md + child. Swift: a GroupBox-like section with header + error border.

### lib/widgets/recipe_form/unit_dropdown.dart (UnitDropdown)

_Unit selector as PillChip opening a bottom sheet of preset units + custom._

Props: value, onChanged(String). PillChip label '{value} ▾' or '单位 ▾', surfaceContainerLowest bg, outlineVariant border, onTap _openSheet. Sheet: ListTile per RecipePresets.units (check on current) + Divider + '自定义…' edit_outlined -> _CustomUnitDialog (TextField '例如：粒'). Swift: a chip-shaped button presenting a sheet/menu of units + custom input.

### lib/widgets/review/base_review_screen.dart (BaseReviewScreen<T>)

_Generic review-screen scaffold (AppBar + list + bottom bar + empty state)._

Generic<T> props: title, items(List<T>), emptyState, itemBuilder(context,index,item), bottomBar, showBottomBarWhenEmpty=false. Scaffold AppBar(title); body empty? emptyState : ListView.separated(pad fromLTRB(lg,md,lg,md), sep SizedBox sm, itemBuilder); bottomNavigationBar = (empty && !showBottomBarWhenEmpty) ? null : bottomBar. Swift: a generic List screen view with toolbar title + bottom bar; empty placeholder.

### lib/widgets/review/review_bottom_bar.dart (ReviewBottomBar)

_Review screens bottom bar: select-all toggle + confirm(count)._

Props: selectedCount, totalCount, confirmLabel, onConfirm?, onToggleSelectAll, onCancel?. allSelected = selectedCount==totalCount && total>0. SafeArea minimum padding. Row: TextButton.icon (deselect/select_all) '取消全选'/'全选' (disabled if total 0); Spacer; optional OutlinedButton '取消'; FilledButton '{confirmLabel} ({selectedCount})' disabled when selectedCount 0. Swift: a bottom toolbar with toggle + primary action.

### lib/widgets/review/action_chip.dart (ProposalActionChip)

_Cycling action chip for intake/deduction proposals._

Two named ctors: .intake(intakeAction IntakeAction{newRow,mergeInto}, mergeTargetLabel?, onToggle); .deduction(deductionAction DeductionAction{deduct,skip}, onToggle). GestureDetector pill (radius pill) Row[label ellipsis + keyboard_arrow_down 14]. _styleFor: intake newRow->('新建 Batch', primarySoft, primaryContainer); mergeInto->('合并' or '合并 → {target}', fkWarnSoft, onSecondaryContainer); deduction deduct->('扣库存', primarySoft, primaryContainer); skip->('跳过', surfaceContainer, outline). Swift: a tappable chip with label/color from action enum.

### lib/widgets/review/provenance_badge.dart (ProvenanceBadge)

_8px origin dot for proposal fields (AI/system/user/edited)._

Props: origin (FieldOrigin{ai,system,user}), userEdited. Color+tooltip switch: userEdited true (any origin)->(fkWarn,'手改'); ai->(primary,'AI 推断'); system->(outline,'系统'); user->(fkWarn,'手填'). Tooltip + 8×8 circle. Swift: a small colored Circle with help tooltip/accessibility label.

### lib/widgets/review/inline_number_stepper.dart (InlineNumberStepper)

_Inline -/value/+ numeric stepper for quantities._

Props: value(String), onChanged(String), min=0, max=9999, suffix?. parsed=double.tryParse(value); canStep when parseable. minus key stepper_minus enabled when parsed>min; plus key stepper_plus enabled when parsed<max. _bump = formatQuantity((current+delta).clamp(min,max)). Buttons 28 circle surfaceContainer Icon 16 (outline when disabled). value Text 15/w600 + optional ' {suffix}'. Swift: HStack Stepper-like with two circular buttons + value; quantity formatting helper.

### lib/widgets/review/picker_sheet.dart (PickerSheet<T> + PickerOption<T>)

_Generic bottom-sheet single-select picker._

PickerOption<T>{value,label,subtitle?}. static show<T>(context,title,options,selected) -> showModalBottomSheet rounded top xl surfaceContainerLowest, returns chosen T?. Body SafeArea: 36×4 outline handle; title sectionTitle; ListView.separated(Divider hair) ListTile label/subtitle, check primary when value==selected, onTap pop(value). Swift: a sheet with a selectable List returning the chosen value; reused by intake/deduction rows.

### lib/widgets/review/deduction_proposal_row.dart (DeductionProposalRow)

_Row for a recipe-deduction proposal (select + batch source + amount)._

Props: proposal(DeductionProposal{selected,recipeIngredientName,requiredQty,candidates List<DeductionCandidate{inventoryRowIndex,displayLabel}>,chosenIndex,action,deductAmount}), onToggleSelected, onToggleAction, onChooseCandidate(int), onChangeAmount(String). chosen = candidate where inventoryRowIndex==chosenIndex (fallback first/empty). isSkip = action==skip. Container surfaceContainerLow(skip)/Lowest, radius md, border hair. Row: FkCheckCircle(selected,22) + name 16/w700 + if requiredQty '菜谱需要 {qty}' + ProposalActionChip.deduction. If !skip && candidates: batch-source GestureDetector -> PickerSheet '扣减来源批次' (inventory_2 icon + chosen.displayLabel/'无可用批次' + unfold_more); '扣减' label + InlineNumberStepper(deductAmount min1). If candidates empty: '库存中没有匹配项,这条将被跳过。'. Swift: a card row with checkbox, action chip, source picker, stepper.

### lib/widgets/review/proposal_row.dart (IntakeProposalRow)

_Editable row for an intake proposal (name/qty/unit/shelf-life/category/storage + provenance + action)._

StatefulWidget props: proposal(IntakeProposal{name,quantity,unit,shelfLifeDays?,category?,storage IconType,selected,origin FieldOrigin,userEdited,action IntakeAction,mergeTargetLabel?} + copyWith), onChanged(IntakeProposal), onToggleSelected, onToggleAction. Inline name editing (_editingName, TextEditingController synced via didUpdateWidget unless editing). Container selected?Lowest:Low, radius md, border primary@0.3 if selected else hair. Header Row: FkCheckCircle(selected,22) + ProvenanceBadge(origin,userEdited) + Expanded _name (tap-to-edit Text or TextField, commit on submit/tapOutside) + ConstrainedBox maxWidth160 ProposalActionChip.intake. Wrap (spacing12 run8): 数量 + InlineNumberStepper(quantity min1) + _unitChip(PickerSheet of 个/只/把/盒/袋/瓶/罐/kg/g/L/ml/份); 保质期 + (shelfLifeDays<=0 -> '未设置 · 点按设置' tap sets 7; else InlineNumberStepper(days min1 suffix天)); _categoryChip(PickerSheet FoodCategories.values, label '分类:{category ?? 其他}'); _storageChip(PickerSheet IconType.values storageLabelFor, label '存:{storageLabel}'). Every edit calls onChanged(copyWith(... userEdited:true)). _pill helper = surfaceContainer pill 14/w600. Swift: an editable card row; inline TextField name; steppers; pickers; copy-with model updates. NOTE shelf-life null/0 means 'no expiry' — never auto-mark expired.

## 外部集成

- google_fonts: runtime-fetched Plus Jakarta Sans (display/headlines/titleLarge/heroStat) + Manrope (titles/body/labels) + JetBrains Mono (image placeholder label). For Swift, bundle these TTFs in the app target — no runtime fetch.
- flutter_svg: SvgPicture.string renders the embedded cartoon SVG strings for CatIcon (9 food categories, 36×36), ZoneIcon (5 storage zones, 24×24), FkNavIcon (5 nav tabs, 24×24). {stroke}/{fill}/{sw} placeholders substituted with hex color + strokeWidth. Swift: convert to SVG/PDF assets or SwiftUI Shape paths; tint via foregroundStyle.
- cached_network_image + flutter_cache_manager: RecipeImage uses CachedNetworkImageProvider (disk+memory cache) for remote URLs, AssetImage for assets/ paths, Image.memory for data: base64 URIs. cacheManager is injectable for tests. Swift: Kingfisher/Nuke or AsyncImage with downsampling + disk cache; UIImage(data:) for base64; bundle for assets/.
- qr_flutter: InviteResultSheet renders QrImageView(inviteUrl) and exports the RepaintBoundary to PNG (pixelRatio 3) for sharing. Swift: CoreImage CIQRCodeGenerator or a SwiftUI QR package; ImageRenderer to export PNG.
- share_plus (SharePlus.instance.share + XFile): InviteResultSheet shares the invite link text and the rendered QR PNG file. Swift: ShareLink / UIActivityViewController.
- Riverpod providers consumed directly by widgets (not part of this subsystem but required wiring): navigationProvider (BottomNavBar/SearchOverlay), searchProvider/searchActiveProvider/searchHistoryProvider/trimmedSearchKeywordProvider/searchFoodDetailsProvider/filteredInventoryProvider/filteredShoppingProvider (SearchOverlay/TopAppBar), syncStatusProvider (SyncStatusBanner), householdSessionControllerProvider (TopAppBar), lowStockItemsProvider/shoppingProvider (LowStockCard/QuickAddField), foodLogMonthStatsProvider (WasteInsightsCard), mealPlanWeekSummaryProvider (WeeklyPlanCard), expiringFallbackRecipeProvider (ExpiringFallbackCard). Swift: these become @Observable stores/derived state.

## Swift 映射

Build a SwiftUI design-system module mirroring the token layer + component layer. Tokens: a Color extension or asset catalog for all AppColors (ARGB hex; light-only — force .preferredColorScheme(.light)); enums of CGFloat for AppRadius/AppSpacing/AppSize; a Shadow ViewModifier chaining two .shadow() calls for the 2-layer card shadow; an animation-tokens enum (durations as Double seconds, easeOutCubic via custom UnitCurve or .easeOut, pressScale 0.97, stagger 0.05s capped at 8); a Font factory bundling Plus Jakarta Sans + Manrope + JetBrains Mono with the exact size/weight ladder; a FoodCategoryStyle enum mirroring FkCategoryPalette (tint/ink, default grain). Urgency: an enum FreshnessStatus {fresh,soon,urgent,expired,low} with a (bg,fg,label) style table = kFkStatusStyles, plus a mapping from the domain FreshnessState (fresh/expiringSoon/urgent/expired) — keep this the single source of truth so no view hardcodes urgency colors. Animated primitives: a PressableButtonStyle (scaleEffect + sensoryFeedback, gated on UIAccessibility.isReduceMotionEnabled), an Entrance modifier (.opacity/.offset onAppear with staggered .delay), a Shimmer modifier (moving LinearGradient .mask via TimelineView), a CheckCircle view — all no-op under Reduce Motion. Components: build SwiftUI views Card, Pill, StatusBadge, IconButton, HeroHeader, DashedBorder (RoundedRectangle.strokeBorder dash), ImagePlaceholder (Canvas stripes), Skeleton + RecipeSkeletonCard, SectionHead, TopBar (custom header since FK replaces the platform nav bar), FreshnessMeter, generic Chip, CategoryAvatar, and the icon sets as Image/Shape assets. Feature views: RecipeCard (horizontal/banner), IngredientCard, the 4 dashboard nav cards, BottomNavBar (custom tab bar with .ultraThinMaterial + center floating button), SearchOverlay (sheet with sectioned List + debounced query), SyncStatusBanner, the household section + invite sheet (ShareLink + QR), shopping QuickAddField, recipe-form widgets (DisclosureGroup-style AI banner, star rating, chip selectors, sheet pickers), and the review widgets (generic List scaffold, bottom bar, action chip, provenance dot, number stepper, PickerSheet, intake/deduction rows). Image loading: AsyncImage/Kingfisher/Nuke with explicit downsampling to the render box (the white-flash fix) + disk cache; UIImage(data:) for base64; bundle for assets/. Use SwiftData @Model types for the domain models referenced (Ingredient/Recipe/Proposal/Household) and @Observable stores for the Riverpod providers; Supabase Swift SDK powers the household-sharing flows behind the invite/member widgets.

## 迁移注意

PARITY-CRITICAL INVARIANTS: (1) FkStatus/kFkStatusStyles + FreshnessState->FkStatus mapping is the SINGLE SOURCE OF TRUTH for urgency colors — do NOT let any card/row/badge re-derive 'expired vs not'; that loses the urgent(coral B5523A ink)/soon(butter 9B7A2A ink)/expired(coral fill, white text) distinction. Domain FreshnessState has only 4 values (fresh/expiringSoon/urgent/expired); FkStatus adds a 5th `low` for shopping/low-stock. (2) Reduce-motion correctness: FkAnimatedPressable/FkEntrance/FkShimmer/FkCheckCircle/SyncStatusBanner/IngredientCard progress all branch on reduce-motion to instant/static — in Flutter this also prevented test pumpAndSettle hangs from infinite/implicit animations; in SwiftUI honor UIAccessibility.isReduceMotionEnabled (esp. for the repeating shimmer — never start a forever-repeat under reduce motion). (3) Shelf-life null/0 means 'NO EXPIRY' (non-perishables), rendered as '未设置 · 点按设置', NOT '0 天' — an item must never be confirmable as expired-on-arrival (IntakeProposalRow). (4) The RecipeImage white-flash fix is load-bearing: decode/downsample MUST be capped to the actual render box and the cache must not evict covers — otherwise switching tabs re-triggers an async first frame showing the fallback ('闪白'). Use a standard cached Image with synchronous cache hit + gaplessPlayback semantics, not a placeholder-first widget. (5) Two distinct system overlay styles: cream pages use dark status-bar icons; the dashboard hero (gradient bleeding behind the status bar) needs LIGHT status-bar icons — TopAppBar text is white for this reason. (6) Color semantics are aliased: tertiary/error fields are reused but mean 'danger' (coral); fkAlert (pure red E5484D) is intentionally different from fkDanger (coral E76F51) and is used only for invite/unread badge dots. (7) fk_category_palette default fallback is grain (not a neutral) — preserve. (8) Icons are two systems: cartoon line SVGs (CatIcon/ZoneIcon/FkNavIcon, hex/strokeWidth substituted) AND Material IconData elsewhere — when porting to SF Symbols keep the cartoon set as custom vector assets to preserve the hand-drawn brand look. (9) ZoneIcon/kFkZoneNames includes door+box zones that the domain IconType enum ({fridge,freezer,pantry}) does NOT have — design-only; IngredientCard._zoneId collapses to those 3. (10) Many number formatting paths go through formatQuantity (utils/quantity_text.dart) with a 2-decimal float fix — reuse one shared quantity formatter in Swift to avoid float drift. SEQUENCING: tokens + urgency mapping + animated primitives first (everything depends on them), then FK primitives (card/pill/icon button/etc), then feature cards, then the Riverpod-bound widgets (need stores ported).

## 开放问题

- google_fonts fetches fonts at runtime in Flutter; confirm the Swift app will bundle Plus Jakarta Sans / Manrope / JetBrains Mono TTFs (licensing + app size) rather than fetch.
- Curves.easeOutCubic is the default 'standard' curve; the closest SwiftUI built-in is .easeOut (not identical). Decide whether to replicate exactly via a custom UnitCurve(controlPoint) for visual parity.
- RecipeImage's render-box decode-cap + cache-non-eviction is the documented fix for tab-switch white-flash; verify the chosen Swift image library (AsyncImage vs Kingfisher/Nuke) supports synchronous cache hits + downsampling so the fallback never flashes on revisit.
- The cartoon SVG icon sets (CatIcon/ZoneIcon/FkNavIcon) have their path data embedded only in these Dart files — confirm whether to convert to SVG/PDF assets, bundle as a custom font, or reimplement as SwiftUI Shapes; SF Symbols would change the hand-drawn brand aesthetic.
- Models referenced (Ingredient, Recipe, Proposal/IntakeProposal/DeductionProposal, DraftField, Household*, FrequentItem, FoodDetails) and providers are owned by other subsystems; this map assumes their Swift equivalents exist before these views can compile.
- FkTab indices (home=0, fridge=1, add=2, recipes=3, shopping=4) come from navigation_provider (FkTab constants) outside this subsystem — confirm the enum values when porting BottomNavBar.
- SwipeRevealDeleteAction is a hand-rolled swipe gesture; decide whether to replace with native SwiftUI .swipeActions (simpler, standard) or replicate the exact 84px reveal/350 velocity thresholds for pixel parity.
