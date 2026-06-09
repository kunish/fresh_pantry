# screens-shopping-meal-waste (`screens-flows`)

**Effort:** L

## 概述

Five screens covering the post-inventory workflow of Fresh Pantry: a category-sorted shopping list with check-off → bulk-intake flow, a 7-day rolling meal-plan calendar with one-tap "缺料" → shopping, a waste-reduction insights dashboard (consumed/wasted/rescued + use-up rate, switchable time windows), and two shared Review screens (IntakeReview and DeductionReview) that gate every inventory mutation through user-confirmable proposals. All five are Riverpod ConsumerWidgets/ConsumerStatefulWidgets reading derived providers; each underlying notifier is a Drift-persisted, household-scoped, sync-enqueuing Notifier holding a one-shot startup seed (pull-to-refresh calls reload() not invalidate). The Review screens are a generic BaseReviewScreen<T> shell parameterized by proposal type; intake feeds applyIntakeProposals (merge-or-new), deduction feeds applyDeductionProposals (cook-time stock reduction that auto-logs consumed departures to the food log, which is the waste-stats source of truth alongside the delete-time "吃完/扔了" outcome sheet).

## 组件(29)

### lib/screens/shopping_list_screen.dart — ShoppingListScreen (ConsumerWidget)

_Category-grouped shopping list with progress card, filter chips, quick-add, check-off, delete+undo, clear-checked, and bulk check-off → intake review._

Reads shoppingListViewProvider (ShoppingListViewState: items, groupedItems, visibleGroups, filter, checkedCount, uncheckedCount; getters total=items.length, progress=total==0?0:checkedCount/total) and collapsedShoppingCategoriesProvider (StateProvider<Set<String>>). Layout: Stack of [RefreshIndicator(onRefresh→shoppingProvider.notifier.reload(), color=primary, bg=surface) wrapping a GestureDetector(onTap unfocus) → CustomScrollView(AlwaysScrollableScrollPhysics) with slivers], plus a bottom Positioned FilledButton CTA shown only when checkedCount>0 (key 'shopping_to_intake_cta', label '已购买的 $checkedCount 项一键入库', minSize Size(inf,48)). Slivers in order: (1) SafeArea+FkTopBar(title '购物清单', subtitle total==0?'清单为空 · 在上方添加食材':'$checkedCount/$total 已完成 · $uncheckedCount 件待购'); (2) _ProgressCard padded h18; (3) QuickAddField padded LTRB(18,14,18,sm); (4) _FilterChipRow; (5) if allItems empty → SliverFillRemaining FkEmptyState(icon shopping_basket_outlined, title '购物清单为空', subtitle '在上方输入框添加需要购买的食材') wrapped in FkEntrance; else SliverPadding(LTRB 18,6,18,120) with _ShoppingContentSliver. _ProgressCard: FkCard with diagonal LinearGradient [primary, primaryContainer], shows '本次采购进度', big done number (Plus Jakarta 800), '/ $total 项', percent = (progress.clamp(0,1)*100).round() top-right (xxxl 800), and a 6px white progress bar (FractionallySizedBox widthFactor=progress.clamp(0,1), track white@0.2). _FilterChipRow: horizontal ListView of 3 pill chips ['全部'=todo+done, '待购买'=todo, '已购'=done] each labeled '$label · $count' when count>0 else label; active chip filled primary white text, inactive white bg + hair border; tap → set shoppingFilterProvider.state. _ShoppingContentSliver: SliverList childCount = visibleEntries.length + (empty?1:0) + (checkedCount>0?1:0); items render _CategoryGroup (in FkEntrance with index), then _FilterEmptyMessage if no visible entries ('没有待购项目'/'没有已购项目' by filter), then a _ClearDoneButton (FkDashedBorder dashed CTA '清空已完成 ($count)') at the end when checkedCount>0. _CategoryGroup: header row with AnimatedRotation chevron (collapsed→-0.25 turns), CatIcon (catId=fkCategoryIdFor(title), palette FkCategoryPalette.of(catId)), title (Plus Jakarta 700 13), count; tap header → _toggleCategory (add/remove from collapsedShoppingCategoriesProvider set). Collapsed → SizedBox.shrink inside AnimatedSize(180ms easeOutCubic); expanded → FkCard with non-scrolling ListView of _ShopRow. _ShopRow: tap row → _onItemChecked; 24px circle check (filled primary + white check_rounded when checked), name (Plus Jakarta 700 md, lineThrough when checked), optional item.detail (manrope xs) when non-empty, trailing close_rounded delete icon; whole row Opacity 0.45 when checked; bottom hairline divider except last. Handlers: _onItemChecked → toggleCheck(item.id); on newly-checked shows snackbar '「name」已购买' with action '加入库存' → _addItemToInventory (seeds intake proposals for [item] via controller.buildProposals, pushes IntakeReviewScreen(title '加入库存'), then controller.removeApplied([item], appliedIds)). _deleteShoppingItem → remove(item.id) then snackbar '「name」已删除' (error color) with '撤销' → add(item back). _confirmClearChecked → showAppConfirmDialog(title '清理已购项目', content '确定要移除所有已勾选的购物项吗？', confirmLabel '清理', destructive) then loops remove() over checked items, snackbar reports removed/total. _openIntakeReviewForChecked → reads checked items, seeds intakeReviewProvider with controller.buildProposals(checked), pushes IntakeReviewScreen(title '已购买项入库') awaiting Set<String> appliedIds, then controller.removeApplied(checked, appliedIds) (removes ONLY rows whose proposal actually applied; null result = cancelled = remove nothing). _refreshShoppingList wraps reload() with FlutterError.reportError on failure + snackbar '购物清单刷新失败'.

### lib/widgets/shopping/quick_add_field.dart — QuickAddField (ConsumerStatefulWidget)

_Inline text field to add a free-text item to the shopping list._

Optional FocusNode param. Nested rounded containers (surfaceContainerLow outer pad lg, surfaceContainerHigh inner) wrapping a borderless TextField: hint '添加食材到清单...', prefixIcon add_circle (primary), suffix IconButton send (primary, tooltip '添加到购物清单'), textInputAction.done. _submit(value): trims; empty→return; calls shoppingProvider.notifier.addFromSuggestion(trimmed); on throw snackbar '添加失败，请重试'; on success clears controller, unfocuses, snackbar '已将「name」加入购物清单' (primary) if added else '「name」已在购物清单中' (tertiary). addFromSuggestion returns false when name already present (name-unique).

### lib/screens/meal_plan_screen.dart — MealPlanScreen (ConsumerWidget)

_Weekly meal-plan calendar: 7-day rolling window unioned with any day that has entries; per-day cards of planned meals with done/delete; top missing-ingredients → shopping CTA._

Reads mealPlanByDayProvider (Map<DateTime,List<MealPlanEntry>>, date-only keys) and mealPlanMissingIngredientsProvider (List<String>). today = MealPlanEntry.dateOnly(now). days = sorted Set of {today+0..+6} ∪ byDay.keys (so past/future planned days never hidden). Scaffold(bg surface) → SafeArea → ListView(bottom pad 40): FkTopBar(title '本周计划', subtitle '排好这周吃什么 · 一键补缺料', onBack→maybePop); if missing non-empty → _MissingCard(count, onTap→_addMissingToShopping); SizedBox lg; if byDay empty → FkEmptyState(icon calendar_month_outlined, title '还没有膳食计划', subtitle '去菜谱页把想吃的加进某一天,这里就能看到一周安排'); else a _DaySection per day. _MissingCard: FkCard(ValueKey 'mp-missing', bg primarySoft, onTap) with white circle add_shopping_cart_outlined icon, '本周还缺 $count 样食材' + '一键加入购物清单' + chevron_right. _DaySection: header = mealPlanDayLabel(date, today) ('今天'/'明天'/'周一'..'周日') + '${date.month}/${date.day}'; if entries empty → _EmptyDayCard (restaurant_outlined + '还没安排'); else FkCard with one _EntryRow per entry. _EntryRow (ConsumerWidget): 44x44 RecipeImage(entry.recipeImageUrl, fallback primarySoft restaurant_menu), recipeName (lineThrough+muted when done), '${entry.servings} 份', a done IconButton (key 'mp-done-{id}', check_circle_rounded primary when done else radio_button_unchecked, tooltip toggles, onPressed→mealPlanProvider.notifier.setDone(id,!done)), and a delete IconButton (key 'mp-del-{id}', close_rounded, onPressed→remove(id)); bottom hairline except last. _addMissingToShopping: loops names calling shoppingProvider.notifier.addFromSuggestion(name) counting added; snackbar '已加入 $added 样食材到购物清单' (primary) or '缺的食材都已在购物清单中' (tertiary); on throw '加入购物清单失败，请重试'. NOTE servings is display-only here ('加入计划' entry point lives in recipe detail, not this screen).

### lib/screens/waste_insights_screen.dart — WasteInsightsScreen (ConsumerWidget)

_Waste-reduction stats dashboard: use-up rate headline, consumed/wasted/rescued metric tiles, most-wasted categories, switchable time window._

Reads wasteStatsWindowProvider (StateProvider<WasteStatsWindow>, default thisMonth), foodLogWindowStatsProvider (FoodLogStats), foodLogWastedByCategoryForWindowProvider (List<({String category,int count})>). Scaffold(bg surface)→SafeArea→RefreshIndicator(onRefresh→foodLogProvider.notifier.reload())→ListView(bottom 40): FkTopBar(title '减废成效', subtitle '${window.label}用掉与浪费 · 越用越省', onBack→maybePop); _WindowSelector (always shown, even when empty); if stats.isEmpty → FkEmptyState(icon eco_outlined, title '${window.label}还没有减废记录', subtitle '做菜用掉、或清理食材时选「吃完 / 扔了」,这里就会统计你的成效'); else: _HeadlineCard (FkCard bg primarySoft: '${windowLabel}用掉率', big usedPct% [usedPct = total==0?0:(consumed/total*100).round(), 40px 800 primary], '${windowLabel}共处理 ${stats.total} 样食材'); Row of three _MetricTile [('用掉', consumed, primary/primarySoft), ('浪费', wasted, fkDanger/tertiaryContainer), ('抢救临期', rescued, fkWarn/fkWarnSoft)]; if byCategory non-empty → '最常浪费' header + _CategoryRow per (category, count) ['$count 样' in fkDanger]. _WindowSelector: Row of _WindowChip over WasteStatsWindow.values [thisMonth '本月', last30Days '近 30 天', last90Days '近 90 天']; active filled primary white, inactive surfaceContainer. _MetricTile: soft-bg rounded box, big value (xl 800 tint) over label (xs 600). All values are item COUNTS, not quantities (quantities are free-text, not summed).

### lib/screens/intake_review_screen.dart — IntakeReviewScreen (ConsumerStatefulWidget)

_Review/edit/confirm intake proposals before they enter inventory; returns the set of applied proposal ids._

Param title (default '审核入库'); shopping flow passes '已购买项入库' or '加入库存'. _isConfirming guards double-tap. Watches intakeReviewProvider (IntakeReviewState{proposals, persistError; selectedCount=count where selected}). ref.listen on persistError → snackbar '草稿保存失败，请重试'. Renders BaseReviewScreen<IntakeProposal>(title, items=state.proposals, emptyState='没有待审核的项目。\n回到上一屏粘贴清单或选择已购买项后再来。', itemBuilder→IntakeProposalRow(key 'intake_proposal_{id}', onChanged→n.updateProposal, onToggleSelected→n.toggleSelected(id), onToggleAction→n.toggleAction(id)) wrapped in FkEntrance(index), bottomBar→ReviewBottomBar(selectedCount, totalCount=proposals.length, confirmLabel _isConfirming?'入库中…':'入库', onConfirm _isConfirming?null:_confirm, onToggleSelectAll→n.toggleSelectAll, onCancel→maybePop)). _confirm: set confirming; appliedIds = intakeReviewProvider.notifier.applyToInventory(inventoryProvider.notifier); snackbar '已入库'; maybePop(appliedIds); on error snackbar '入库失败，请重试'; finally reset confirming. applyToInventory delegates to applyAndClear(()→inventory.applyIntakeProposals(proposals)) which clears the draft after.

### lib/screens/deduction_review_screen.dart — DeductionReviewScreen (ConsumerStatefulWidget)

_Review/edit/confirm cook-time inventory deductions; on confirm reduces stock and auto-logs consumed departures._

Param title (default '审核扣库存'). Watches deductionReviewProvider (DeductionReviewState{proposals; selectedCount=count selected && deductible; deductibleCount=count deductible}; deductible = action==deduct && has chosen candidate). BaseReviewScreen<DeductionProposal>(showBottomBarWhenEmpty:true, emptyState='这道菜的食材没有可扣减的库存项。', itemBuilder→DeductionProposalRow(key 'deduction_proposal_{id}', onToggleSelected→toggleSelected, onToggleAction→toggleAction, onChooseCandidate→chooseCandidate(id,idx), onChangeAmount→updateDeductAmount(id,v)), bottomBar→ReviewBottomBar(selectedCount, totalCount=deductibleCount, confirmLabel _isConfirming?'扣减中…':'确认扣减', onConfirm→_confirm, onToggleSelectAll, onCancel→maybePop)). _confirm: deductionReviewProvider.notifier.applyToInventory(inventoryProvider.notifier); snackbar '已扣减库存'; maybePop(); on error '扣减失败，请重试'. Launched from recipe_detail_screen '我做了' button (key 'recipe_cooked_action'): seeds proposals via DeductionProposalFactory.forRecipe(recipe, inventory) then pushes this screen.

### lib/widgets/review/base_review_screen.dart — BaseReviewScreen<T> (StatelessWidget)

_Generic Review shell: app bar, separated list of proposal rows, bottom action bar._

Params: title, items:List<T>, emptyState:Widget, itemBuilder(context,index,item)→Widget, bottomBar:Widget, showBottomBarWhenEmpty=false. Scaffold(AppBar(Text title)); body = empty? emptyState : ListView.separated(pad LTRB lg,md,lg,md, separator SizedBox(height sm)); bottomNavigationBar = (isEmpty && !showBottomBarWhenEmpty) ? null : bottomBar.

### lib/widgets/review/review_bottom_bar.dart — ReviewBottomBar (StatelessWidget)

_Select-all toggle + cancel + confirm-with-count footer for review screens._

Params selectedCount,totalCount,confirmLabel,onConfirm?:VoidCallback,onToggleSelectAll,onCancel?. allSelected = selectedCount==totalCount && total>0. SafeArea(minimum LTRB lg,sm,lg,md) Row: TextButton.icon [deselect/select_all icon + '取消全选'/'全选', enabled when total>0], Spacer, optional OutlinedButton '取消'→onCancel, FilledButton '$confirmLabel ($selectedCount)' (disabled when selectedCount==0).

### lib/widgets/review/proposal_row.dart — IntakeProposalRow (StatefulWidget)

_Editable card for one intake proposal: name, select checkbox, provenance dot, action chip, qty+unit+shelf-life steppers, category+storage pickers._

Local _editingName state + TextEditingController synced from proposal.name when not editing. Container bg = selected?surfaceContainerLowest:surfaceContainerLow, border = selected?primary@0.3:hair. Row1: FkCheckCircle(checked=p.selected, size 22, onTap→onToggleSelected), ProvenanceBadge(origin, userEdited), tappable name (tap→edit inline TextField; commit on submit/tapOutside via onChanged copyWith(name,userEdited:true); shows '(无名)' if empty), ProposalActionChip.intake(intakeAction=p.action, mergeTargetLabel, onToggle→onToggleAction) constrained maxWidth 160. Row2 Wrap: '数量' + InlineNumberStepper(value=p.quantity, min 1, onChanged→copyWith(quantity,userEdited:true)) + _unitChip; '保质期' + (if (shelfLifeDays??0)<=0 a '未设置 · 点按设置' pill that on tap sets shelfLifeDays:7, else InlineNumberStepper(value=shelfLifeDays.toString(), min 1, suffix '天', onChanged→copyWith(shelfLifeDays:int.tryParse??1))); _categoryChip ('分类:${category??'其他'}' → PickerSheet over FoodCategories.values); _storageChip ('存:${storageLabelFor(storage)}' → PickerSheet over IconType.values labeled storageLabelFor). _unitChip PickerSheet options: 个/只/把/盒/袋/瓶/罐/kg/g/L/ml/份. All edits set userEdited:true.

### lib/widgets/review/deduction_proposal_row.dart — DeductionProposalRow (StatelessWidget)

_Card for one cook-time deduction: ingredient name, required qty, select checkbox, deduct/skip chip, batch source picker, deduct amount stepper._

chosen = first candidate where inventoryRowIndex==chosenIndex (else first, or sentinel {-1,''} when none). isSkip = action==skip. Container bg = isSkip?surfaceContainerLow:surfaceContainerLowest, hair border. Row1: FkCheckCircle(p.selected, size 22, onTap→onToggleSelected), recipeIngredientName (lg 700, ellipsis), '菜谱需要 ${requiredQty}' when non-empty, ProposalActionChip.deduction(action, onToggle→onToggleAction). If !isSkip && candidates non-empty: a tappable batch-source box (inventory_2_outlined + chosen.displayLabel or '无可用批次' + unfold_more) → PickerSheet<int>(title '扣减来源批次', options candidates [value inventoryRowIndex, label displayLabel], selected chosenIndex) → onChooseCandidate(picked); then '扣减' + InlineNumberStepper(value=p.deductAmount, min 1, onChanged→onChangeAmount). Else if candidates empty: '库存中没有匹配项,这条将被跳过。'

### lib/widgets/review/action_chip.dart — ProposalActionChip

_Pill chip showing/toggling a proposal's action._

Two named ctors. .intake: newRow→('新建 Batch', primarySoft/primaryContainer); mergeInto→(mergeTargetLabel==null?'合并':'合并 → $label', fkWarnSoft/onSecondaryContainer). .deduction: deduct→('扣库存', primarySoft/primaryContainer); skip→('跳过', surfaceContainer/outline). Pill with keyboard_arrow_down icon, tap→onToggle.

### lib/widgets/review/inline_number_stepper.dart — InlineNumberStepper

_Minus/value/plus stepper over a string-typed number with optional suffix._

Params value:String, onChanged, min=0, max=9999, suffix?. parsed=double.tryParse(value); minus enabled when parsed>min, plus when parsed<max; _bump clamps then onChanged(formatQuantity(next)). 28px circular buttons (keys 'stepper_minus'/'stepper_plus'). Non-numeric value disables both buttons.

### lib/widgets/review/picker_sheet.dart — PickerSheet<T> / PickerOption<T>

_Modal bottom-sheet single-select picker used for unit/category/storage/batch._

PickerOption{value:T, label:String, subtitle?}. Static show<T>(context, title, options, selected) → showModalBottomSheet returning T? (null on dismiss). Sheet: drag handle, title (sectionTitle), ListView.separated of ListTile(title=label, subtitle?, trailing check when value==selected) → pop(value).

### lib/widgets/review/provenance_badge.dart — ProvenanceBadge

_8px colored dot marking field provenance._

(origin,userEdited): userEdited→(fkWarn,'手改'); ai→(primary,'AI 推断'); system→(outline,'系统'); user→(fkWarn,'手填'). Tooltip-wrapped circle. Shopping-derived intakes use origin=system.

### lib/utils/food_departure_sheet.dart — showFoodDepartureOutcomeSheet

_Delete-time 'consumed vs wasted' prompt — the manual-removal source of truth for waste stats._

showFoodDepartureOutcomeSheet(context, {itemName?, count=1}) → Future<FoodLogOutcome?>. Title = '「$itemName」要移除' or '移除 $count 样食材'; subtitle '它怎么了?用于统计你的减废成效'. Two _OutcomeTile: '吃完 / 用掉了' (check_circle_outline, primary, key 'departure-consumed' → consumed), '没吃完,扔了' (delete_sweep_outlined, error, key 'departure-wasted' → wasted), plus '取消' (key 'departure-cancel' → null). Caller (inventory remove/removeMany) passes the returned outcome; null = abandon delete.

### lib/providers/shopping_provider.dart — ShoppingNotifier + derived providers

_Household-scoped shopping list state, persistence, sync, and the derived view/group/count providers._

State List<ShoppingItem>. build()=repo.loadAll() (one-shot seed). syncEntityType=shoppingItem. reload()=repo.loadAllFor(activeHouseholdId). add(item): normalizes + ensures unique id; name-unique (shoppingItemNameKey) → returns false if blank or duplicate; optimistic state+queuePersistence(rethrow) with rollback; enqueueSync create with item.toJson. remove(id): optimistic remove + persist + enqueueSync delete {deletedAt utc iso} baseVersion=remoteVersion. toggleCheck(id): flips isChecked, persist, enqueueSync toggleChecked {isChecked} baseVersion. addFromIngredient/addFromSuggestion(name): builds ShoppingItem(newId 'si_<ms>', name, detail '', category=FoodKnowledge.categoryFor(name)) → add. replaceFromRemote(items, rethrowOnError=false): dedup by id, optimistic with rollback. Providers: shoppingProvider; shoppingFilterProvider(StateProvider default all); collapsedShoppingCategoriesProvider(StateProvider<Set<String>>); shoppingListViewProvider(Provider→ShoppingListViewState). enum ShoppingFilter{all,todo,done}. groupShoppingItems: groups by item.category then orders groups by _shoppingCategoryRank = index in FoodCategories.values [乳品蛋类,果蔬生鲜,肉类海鲜,香料草本,其他]; unknown/blank sort last; stable on ties by insertion order. filterShoppingGroups: all→passthrough; todo→!isChecked; done→isChecked, dropping empty groups. shoppingCountsFor → (checked, unchecked).

### lib/providers/meal_plan_provider.dart — MealPlanNotifier + derived providers

_Weekly meal-plan state (one entry = one meal), persistence, sync, day-grouping, missing-ingredient derivation, week summary._

State List<MealPlanEntry>. build()=repo.loadAll(); syncEntityType=mealPlanEntry. reload()=loadAllFor(activeHouseholdId). _mutate wraps queuePersistence(save+state). addEntry({date, recipe, servings=1})→creates MealPlanEntry(id=newSyncEntityId(), date, recipeId/Name/ImageUrl from recipe, servings max 1) then enqueueSync create; returns id. remove(id): mutate filter-out + enqueueSync delete {deletedAt}. setDone(id,done)/moveToDate(id,date) → _updateById → copyWith + enqueueSync update. mealPlanByDayProvider: Map<DateTime,List> grouped by entry.date (date-only). mealPlanMissingIngredientsProvider: distinct ingredient names from NOT-done planned entries not covered by inventory; resolves recipe from presets (recipesProvider data) ∪ customRecipes (custom shadows preset on id clash); entries with missing recipe contribute nothing; matching via recipeIngredientMatchesInventory (substring, case-insensitive); ready for addFromSuggestion. mealPlanWeekSummaryProvider: (upcoming in [today,+7), today count, missing.length).

### lib/providers/food_log_provider.dart — FoodLogNotifier + stats providers

_Append-only food-departure log (waste-stats source of truth) and pure aggregation providers._

State List<FoodLogEntry>; build()=repo.loadAll(); NO SyncEnqueue yet (sync is a later round, local-only). foodLogRecentWindow = Duration(days:90); _recentCutoffMs = now.utc - 90d. record(entry): no-op on blank id; queuePersistence(repo.append + append to state). undoRecord(id): repo.deleteEntry + remove from state (reverses an undone delete). reload()=repo.loadRecentFor(household, sinceMs=cutoff). replaceFromRemote(entries). FoodLogStats{consumed,wasted,rescued; total=consumed+wasted; wasteRate=total==0?0:wasted/total; isEmpty=total==0}; equality+hashCode over 3 fields. computeFoodLogStats(entries, since): for each entry at/after since.utc — consumed++ (and rescued++ if wasExpiring) when isConsumed, else wasted++. enum WasteStatsWindow{thisMonth '本月', last30Days '近 30 天', last90Days '近 90 天'} with since(): thisMonth=_monthStart() (1st 00:00 local), last30Days=now-30d, last90Days=now-90d (=window cap). Providers: wasteStatsWindowProvider(StateProvider default thisMonth), foodLogMonthStatsProvider (fixed month, dashboard card), foodLogWindowStatsProvider (windowed), foodLogWastedByCategoryProvider / ...ForWindowProvider (List<(category,count)> wasted-only, desc by count). foodLogWastedByCategory pure helper.

### lib/providers/shopping_intake_controller.dart — ShoppingIntakeController

_ViewModel seam between shopping list and intake review: build proposals + remove only-applied source rows._

shoppingIntakeControllerProvider(Provider). buildProposals(items)=IntakeProposalFactory.fromShoppingItems(items, inventoryProvider read). removeApplied(source, appliedIds): no-op if appliedIds empty; per source item, skip unless appliedIds contains IntakeProposalFactory.proposalIdForShoppingItem(item.id) ('ix_<itemId>'); sequential per-item try/catch remove (a row that entered inventory but failed to clear is left for retry; cancelled/deselected proposals never silently discarded).

### lib/providers/intake_review_provider.dart — IntakeReviewNotifier + IntakeReviewState

_Holds editable intake proposals with debounced draft persistence and apply-to-inventory._

IntakeReviewState{proposals:List<IntakeProposal>, persistError?; selectedCount}. build() loads persisted draft from intakeReviewDraftRepoProvider. seed(proposals) replaces + schedules draft persist. clear() empties + persists. toggleSelected(id): flip selected. toggleAction(id): no merge target→no-op; perishable newRow→locked (perishables always new Batch); else toggle newRow↔mergeInto with userEdited. updateProposal(updated): _coerceActionForRules (mergeInto+perishable → forced newRow) then replace. toggleSelectAll. applyToInventory(inventory)=applyAndClear(()→inventory.applyIntakeProposals(proposals)) returning applied ids set; clears draft after. _schedulePersistDraft persists state.proposals async, surfacing persistError on failure. IntakeProposal model: {id, name, quantity:String, unit:String, category:String?, storage:IconType, shelfLifeDays:int?, action=newRow, mergeTargetId?, mergeTargetLabel?, origin=ai, userEdited=false, selected=true}.

### lib/providers/deduction_review_provider.dart — DeductionReviewNotifier + DeductionReviewState

_Holds cook-time deduction proposals; apply reduces inventory + auto-logs consumed departures._

DeductionReviewState{proposals; selectedCount=selected&&deductible; deductibleCount=deductible}; deductible = action==deduct && a candidate has inventoryRowIndex==chosenIndex. build()=empty (NOT persisted, unlike intake). seed(proposals). toggleSelected(id): force false if not deductible, else flip. toggleAction(id): deduct→skip+deselect; skip→ if no chosen candidate stays skip+deselect, else deduct+select. chooseCandidate(id,idx): if idx is a known candidate → chosenIndex=idx, action=deduct, selected=true. updateDeductAmount(id,amount): trim; if parses to <=0 coerce '1'. toggleSelectAll over deductible only. applyToInventory(inventory)=applyAndClear(()→inventory.applyDeductionProposals(proposals)). DeductionProposal model: {id, recipeIngredientName, requiredQty:String, candidates:List<DeductionCandidate>(unmodifiable), chosenIndex:int (-1 when skip), deductAmount:String, action=deduct, selected=true}; .empty(...) ctor → no candidates, chosenIndex -1, deductAmount '0', action skip, selected false. DeductionCandidate{inventoryRowIndex:int (positional, selection key only), displayLabel, inventoryRowId='', inventoryRowName='', inventoryRowUnit='' (stable identity for apply-time re-resolution)}.

### lib/services/intake_proposal_factory.dart — IntakeProposalFactory

_Builds intake proposals from shopping items / drafts, resolving default merge-or-new action against live inventory._

proposalIdForShoppingItem(itemId)='ix_$itemId' (single owner of the scheme). fromShoppingItems(items, inventory): per item parse detail via _parseDetail (empty→('1','份'); else parseLeadingQuantity → (magnitude, remainder.isEmpty?'份':remainder); unparseable→('1', trimmed)); infer storage from first inventory row matching name(lower)+unit (else IconType.fridge); shelfLifeDays=null; origin=system. _build: action=ProposalPlanner.computeIntakeDefaultAction(candidate, inventory); mergeTargetId=targetIndex.toString(); mergeTargetLabel='${inv.name} ${inv.quantity}${inv.unit}'. isSinglePrefill: exactly 1 proposal that is newRow (bypasses review). fromDrafts variant for AI-parsed intakes (origin ai).

### lib/services/deduction_proposal_factory.dart — DeductionProposalFactory

_Converts a cooked recipe into reviewable deduction proposals against inventory._

forRecipe(recipe, inventory): per recipe ingredient i, candidates=ProposalPlanner.fuzzyMatchInventoryRows(ri.name, inventory); empty→DeductionProposal.empty(id 'd_{recipe.id}_{i}', name, requiredQty=ri.amount); else DeductionProposal(id, name, requiredQty, candidates, chosenIndex=candidates.first.inventoryRowIndex, deductAmount=_initialDeductAmount). _initialDeductAmount: parse recipe magnitude/unit; if none/≤0→'1'; if recipe unit vs chosen row unit incompatible→'1'; else formatQuantity(magnitude) (a safe 'used one' default, never silently 0).

### lib/providers/inventory_provider.dart — InventoryNotifier (apply + departure-log methods only)

_Applies intake/deduction proposals to inventory and logs food departures (the bridge between Review screens and waste stats)._

applyIntakeProposals(proposals)→Set<String> appliedIds: for each selected proposal, if mergeInto re-resolve via IngredientIdentity.resolveMergeTarget(name,unit,storage,category,liveInventory) (never the stale positional index); mergeIndex<0 → create new row (sync create); else sum quantities + refreshIngredientFreshness + sync intake op; optimistic state+persist w/ rollback then enqueueSyncBatch; returns set of applied proposal ids. applyDeductionProposals(proposals): resolve each selected deduct to live row by identity, aggregate amounts per row (two proposals→same row net once); non-numeric stock left untouched (never coerced to 0/deleted); remaining<=0 → remove row + sync delete + collect as consumedDeparture; else update qty + sync deduction; after persist, _logDeparture(item, consumed) for each emptied row. _logDeparture(item, outcome): newSyncEntityId, FoodLogEntry(name, category=item.category??其他, outcome, loggedAt=now, wasExpiring=isNotFreshIngredient(item)) → foodLogProvider.notifier.record; returns id. remove(index, {outcome?}) / removeMany(targets, {outcome?}): optimistic delete + sync; when outcome given, _logDeparture each and return the log id(s) so an undo can call foodLogProvider.notifier.undoRecord.

### lib/models/shopping_item.dart — ShoppingItem

_Shopping list row model with sync metadata._

Fields: id:String, name:String, detail:String, imageUrl:String?, category:String, isChecked=false, remoteVersion=0, clientUpdatedAt:DateTime?, deletedAt:DateTime?. newId()='si_<ms>'. fromIngredient(ingredient,{id?}): detail='${quantity} ${unit}', category=ingredient.category??其他. Equality/hashCode by id only. toJson/fromJson with dateTimeToJsonValue helpers; category defaults to 其他 on parse.

### lib/models/meal_plan_entry.dart — MealPlanEntry

_One planned meal on a given day (recipe snapshot + state)._

Fields: id, date:DateTime (normalized to local midnight via dateOnly in ctor), recipeId, recipeName, recipeImageUrl?, servings=1, done=false, remoteVersion=0, clientUpdatedAt?, deletedAt?. dateOnly(v)=DateTime(y,m,d). dateKey(v)='yyyy-MM-dd'. Equality by id. toJson date→dateKey; fromJson throws FormatException when date missing/unparseable (repo skips dirty row); servings default 1, done default false. Recipe name/image are redundant snapshots so calendar renders without recipe lookup and survives recipe deletion/rename.

### lib/models/food_log_entry.dart — FoodLogEntry + FoodLogOutcome

_One food-departure event (consumed/wasted) — waste-stats truth source._

Fields: id, name, category=其他, outcome:FoodLogOutcome, loggedAt:DateTime (ctor →toUtc()), wasExpiring=false, remoteVersion=0, clientUpdatedAt?, deletedAt?. newId()='fl_<ms>'. isConsumed/isWasted/rescuedExpiring(=consumed&&wasExpiring). Equality by id. toJson outcome→.name, loggedAt→iso8601; fromJson throws FormatException when loggedAt missing/unparseable; outcome via FoodLogOutcome.fromName (unknown→consumed, conservative). enum FoodLogOutcome{consumed, wasted}. Quantities deliberately not tracked — item-count semantics only.

### lib/models/proposal.dart — Proposal hierarchy

_Sealed proposal model: IntakeProposal, DeductionProposal, DeductionCandidate, action/origin enums._

enum IntakeAction{newRow, mergeInto}; DeductionAction{deduct, skip}; FieldOrigin{ai, system, user}. sealed Proposal{id, selected=true}. IntakeProposal adds name, quantity:String, unit:String, category:String?, storage:IconType, shelfLifeDays:int?, action=newRow, mergeTargetId?, mergeTargetLabel?, origin=ai, userEdited=false; copyWith preserves origin. DeductionCandidate{inventoryRowIndex:int (positional selection key, NOT apply-time truth), displayLabel, inventoryRowId='', inventoryRowName='', inventoryRowUnit=''}. DeductionProposal{recipeIngredientName, requiredQty:String, candidates(unmodifiable), chosenIndex:int, deductAmount:String, action=deduct}; .empty factory for no-match rows.

### lib/data/food_categories.dart — FoodCategories

_Canonical food category set + normalization + perishability, driving shopping sort and intake merge/new rule._

Constants: dairyAndEggs '乳品蛋类', freshProduce '果蔬生鲜', meatAndSeafood '肉类海鲜', herbsAndSpices '香料草本', other '其他'. values order = [乳品蛋类,果蔬生鲜,肉类海鲜,香料草本,其他] (the shopping aisle sort key). _aliases maps many legacy/synonym strings→canonical (unknown→other). normalize(category)→canonical or null on blank. _perishable={freshProduce, meatAndSeafood, dairyAndEggs}; isPerishable(category). Perishables always create a new Batch on intake (cannot toggle to merge).

## 外部集成

- Supabase family-sharing sync: ShoppingNotifier and MealPlanNotifier mix in SyncEnqueue and call enqueueSync per mutation (create/update/delete/intake/deduction/toggleChecked), writing to a local sync outbox scoped by activeHouseholdId; no-ops when local-only (no household). SyncEntityType.shoppingItem and .mealPlanEntry. Each entity carries SyncMetadata{remoteVersion, clientUpdatedAt, deletedAt}; deletes enqueue {deletedAt: utc iso} with baseVersion=remoteVersion. replaceFromRemote(rethrowOnError) is the inbound-sync apply path.
- FoodLog sync NOT YET wired: FoodLogNotifier is explicitly local-only (no SyncEnqueue) — household sync for departures is a deferred round. replaceFromRemote exists for future sync/backup import but no enqueue on record/undoRecord.
- Drift (SQLite) local persistence: all three notifiers persist via repos (shoppingRepoProvider/mealPlanRepoProvider/foodLogRepoProvider) scoped by household id; pull-to-refresh uses reload()/loadAllFor()/loadRecentFor() (NEVER ref.invalidate — build() returns a one-shot startup seed that would reload empty). Intake-review draft persisted via intakeReviewDraftRepoProvider (survives app relaunch); deduction review is NOT persisted.
- Recipe library (presets + custom): mealPlanMissingIngredientsProvider resolves each entry's recipe from recipesProvider (async preset library) ∪ customRecipesProvider (custom shadows preset on id clash) to compute the missing-ingredient set fed to the shopping list.

## Swift 映射

"Screens → SwiftUI views observing @Observable view-model/store types (one per subsystem) injected via @Environment; replace Riverpod derived providers with computed properties on @Observable stores. ShoppingListScreen → SwiftUI ScrollView + custom collapsible category sections (DisclosureGroup or manual + matchedGeometry/animation), .refreshable→reload(), a sticky bottom bar (safeAreaInset(edge:.bottom)) for the bulk-intake CTA; ShoppingStore @Observable holds [ShoppingItem] with computed grouped/filtered/counts mirroring groupShoppingItems (sort by FoodCategories.values index) + filterShoppingGroups. MealPlanScreen → List/ScrollView of day sections; MealPlanStore computes byDay + missing set (the latter reading a RecipeStore). WasteInsightsScreen → ScrollView with headline/metric tiles/category rows; FoodLogStore exposes windowed FoodLogStats + wasted-by-category, window selection an @Observable enum. IntakeReview/DeductionReview → a generic SwiftUI ReviewView<Proposal> matching BaseReviewScreen with a bottom action bar; ReviewStore types own toggle/select/apply logic; pickers via .confirmationDialog or a custom bottom sheet (PickerSheet), steppers as a custom string-number Stepper. SwiftData @Model types: ShoppingItem, MealPlanEntry (store dateOnly + a dateKey index), FoodLogEntry (append-only; index loggedAt), each with remoteVersion/clientUpdatedAt/deletedAt for sync; Proposal/DeductionCandidate stay plain structs (transient, not persisted) except the intake-review draft which can persist as Codable in a lightweight store or a single @Model draft row. Sync: Supabase Swift SDK with a local outbox table + an actor SyncEngine enqueuing ops (create/update/delete/intake/deduction/toggleChecked) keyed by household id; FoodLog sync deferred to match Flutter. Food-departure outcome sheet → SwiftUI .sheet/.confirmationDialog returning FoodLogOutcome?. Use Swift 6 actors for repo/persistence boundaries; keep all 'never silently deduct 0 / never coerce non-numeric stock / re-resolve merge & deduction targets by stable identity at apply time' invariants verbatim."

## 迁移注意

"PARITY-CRITICAL INVARIANTS: (1) Shopping category sort = position in FoodCategories.values [乳品蛋类,果蔬生鲜,肉类海鲜,香料草本,其他], unknown/blank last, stable on ties — do not sort alphabetically. (2) Shopping items are NAME-UNIQUE (shoppingItemNameKey); add() returns false (not error) on duplicate; the UI shows '已在购物清单中'. (3) Shopping check-off does NOT auto-add to inventory; only the explicit intake-review apply does, and ONLY rows whose proposal id (scheme 'ix_<itemId>') is in the returned appliedIds are removed from the list — a cancelled review (null) removes nothing, a deselected proposal stays. removeApplied is per-item try/catch so a row that entered inventory but failed to clear stays for retry. (4) Intake merge target and deduction target are re-resolved by STABLE IDENTITY against live inventory at apply time, never by the positional index captured at proposal time (list can reorder/restore-from-draft). (5) Perishable categories (果蔬生鲜/肉类海鲜/乳品蛋类) ALWAYS create a new Batch — toggleAction/updateProposal lock/coerce them out of mergeInto. (6) Deduction: never silently deduct 0 (amount<=0 coerced to '1' in UI, skipped in apply); non-numeric existing stock (适量/半盒) is left UNTOUCHED, never coerced to 0 and deleted; two proposals resolving to the same row net into one deduction. (7) shelfLifeDays null/0 means 'no expiry' — show '未设置 · 点按设置' (default 7 on tap), never a misleading '0 天'. (8) Waste stats count ITEMS not quantities; rescued = consumed && wasExpiring; FoodLogOutcome unknown→consumed (conservative). wasteStatsWindow.last90Days must equal foodLogRecentWindow (90d) so a query never reaches past the hydrated in-memory slice. (9) MealPlanEntry.date normalized to local midnight; calendar day set = {today+0..+6} ∪ any day with entries (never hide out-of-window plans). MealPlanEntry.servings is currently DISPLAY-ONLY (does not scale missing-ingredient computation). recipeName/recipeImageUrl are redundant snapshots so the calendar survives recipe deletion/rename. (10) Pull-to-refresh must reload from DB, NOT recreate the store from its startup seed (would reload empty). (11) MealPlanEntry/FoodLogEntry fromJson THROW on missing date/loggedAt — repo skips dirty rows, no silent fallback. (12) Deduction emptying a row auto-logs a CONSUMED departure (cook flow); manual inventory delete prompts the outcome sheet — these are the only two waste-stats inputs (shopping-intake does NOT log). FoodLog sync is intentionally deferred (local-only) — replicate that staging unless full-parity-day-one requires syncing it (open question)."

## 开放问题

- Target says 'full family-sharing parity from day one', but FoodLogNotifier is intentionally local-only in Flutter (no SyncEnqueue; sync is a deferred round). Decide whether the Swift FoodLog must sync on day one (would need a new Supabase table + outbox wiring not present in Flutter) or match Flutter's local-only staging.
- DeductionReview state is NOT persisted as a draft (unlike IntakeReview which restores from intakeReviewDraftRepo across launches). Confirm this asymmetry is intentional and should be preserved.
- mealPlanMissingIngredientsProvider does NOT scale by MealPlanEntry.servings (servings is display-only). Confirm Swift should keep servings as a non-functional snapshot or implement servings-aware scaling (the model comment hints at future scaling).
- ProposalPlanner / IngredientIdentity (computeIntakeDefaultAction, fuzzyMatchInventoryRows, resolveMergeTarget, isPerishable) were referenced but not read here — exact fuzzy-match and merge-target identity rules live there and must be mapped by the inventory/services subsystem owner for the Review screens to behave identically.
- FkCategoryPalette / fkCategoryIdFor (shopping category icon+color) and the theme tokens (AppColors/AppSpacing/AppFontSize/AppRadius, Google Fonts Manrope/Plus Jakarta Sans) are referenced but defined elsewhere; the design-system subsystem must supply exact values for pixel parity.
- RecipeImage widget (network image with disk cache + fallback) and its caching behavior (ImageCache sizing per the project memory) are reused by the meal-plan rows; its exact decode/caching strategy is owned by the shared-widgets subsystem.
