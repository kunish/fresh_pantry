# screens-auth-settings (`screens-auth`)

**Effort:** L

## 概述

This subsystem covers the four "account & config" screens of Fresh Pantry: (1) AuthGateScreen — the root gate that decides login form / household bootstrap / invite preview / authenticated child based on session state, driving email OTP login (6-digit verifyOTP, no magic-link round-trip), invite deep-link capture, and household creation/join; (2) SettingsScreen ("我的") — profile card, stat counts, household-share entry, expiry-reminder toggles (with notification-permission gating), clipboard JSON backup export/import, dietary-preference chips (persisted as household category_preferences), and navigation links; (3) AiSettingsScreen — OpenAI-compatible endpoint/key/model/timeout config with a live connection-test probe, stored plaintext locally; (4) HouseholdScreen — full household management (rename, link/email invites with QR sheet, member list/removal, pending-invite revoke, switch/leave/dissolve, accept incoming invites). All household state flows through a single StateNotifier (HouseholdSessionController) backed by a Supabase gateway (auth + RPCs). The active household id is projected into a root-resident StateProvider so root-stored sync notifiers target the right household. Settings (reminders, AI) persist to local key-value storage; dietary prefs and all household data persist to Supabase.

## 组件(16)

### lib/screens/auth_gate_screen.dart

_Root auth gate: routes between login form, household bootstrap, invite preview/reminder, and the authenticated child based on HouseholdSessionState; captures invite deep links._

ConsumerStatefulWidget(authenticatedChild: Widget, initialInviteToken: String?). Controllers: _emailController, _otpController, _householdNameController (default text '我的家庭'), _inviteController. State fields: _pendingInviteToken:String?, _inviteInputError:String?, _lastPreviewToken:String?, _emailError:String?, _otpError:String?, _dismissedInviteIds:Set<String>, _inviteLinkSubscription:StreamSubscription<String>?.

initState: if initialInviteToken!=null parse via inviteTokenFromInput → set _pendingInviteToken + populate _inviteController. Future.microtask → householdSessionControllerProvider.notifier.refreshHouseholds(). _listenForInviteLinks(): reads inviteLinkSourceProvider, consumeInitialLink().then(_handleIncomingInviteLink), subscribes to incomingLinks stream. _handleIncomingInviteLink(link): inviteTokenFromInput → setState _pendingInviteToken + _inviteController.text=link.

TOP-LEVEL FN selectedHouseholdIdForSession(session): returns selectedHouseholdId if it's a joined household, else households.first.id, else '' when empty.

build(): watches householdSessionControllerProvider. ref.listen on householdSessionControllerProvider.select(selectedHouseholdIdForSession) → writes selectedHouseholdIdStateProvider.notifier.state (PROJECTION; must run outside build via listener, NOT a nested ProviderScope override). ROUTING ORDER: (a) if _pendingInviteToken!=null && session.isAuthenticated → _ensureInvitePreviewLoaded + _buildInvitePreview. (b) if !isLoading && isAuthenticated && firstPendingInviteReminder!=null → _buildPendingInviteReminder. (c) if households.isNotEmpty → authenticatedChild. (d) if isLoading → _buildStartupScreen. (e) if isAuthenticated → _buildHouseholdBootstrap. (f) else → _buildLoginForm.

LOGIN FORM: title '登录 Fresh Pantry'. Email TextField (autofillHints email, keyboardType emailAddress, errorText _emailError, onSubmitted _sendOtp, disabled when session.isSubmitting). If session.error!=null show _ErrorText. If session.sentOtpToEmail.isEmpty → FilledButton.icon '发送验证码' (icon mail_outline; spinner+'发送中...' when submitting) calling _sendOtp. Else → _OtpSentText('验证码已发送至 $email，请输入邮件中的验证码'), OTP TextField (autofillHints oneTimeCode, keyboardType number, FilteringTextInputFormatter.digitsOnly, maxLength 6, counterText '', errorText _otpError, onSubmitted _verifyOtp), FilledButton.icon '验证并登录' (icon login; '验证中...' when submitting) → _verifyOtp, TextButton '重新发送验证码' → _sendOtp. Below: _InviteInputSection(buttonLabel '保存邀请').

_sendOtp(): trims email; validates regex ^[^@\s]+@[^@\s]+\.[^@\s]+$ else _emailError='请输入有效的邮箱地址'; clears _otpController; calls controller.sendOtp(email). _verifyOtp(): trims code; empty → _otpError='请输入验证码'; calls controller.verifyOtp(code).

HOUSEHOLD BOOTSTRAP: title '创建家庭配置', body '首次登录后需要创建一个家庭，之后可以在设置里邀请家人加入。'. TextField (_householdNameController labelText '家庭名称', onSubmitted _createHousehold). FilledButton.icon '创建家庭' (icon home_outlined; '创建中...'). _InviteInputSection(buttonLabel '查看邀请'). _createHousehold(): controller.createHousehold(_householdNameController.text).

_saveInviteInput(): inviteTokenFromInput(_inviteController.text); null → _inviteInputError='请输入有效的邀请链接或邀请码'; else setState _pendingInviteToken + reset _lastPreviewToken.

INVITE PREVIEW (maxWidth 460): title '家庭邀请'; if isPreviewLoading→spinner; else if invitePreview!=null→_InvitePreviewCard; else if error→_ErrorText. FilledButton.icon '接受邀请' (icon group_add_outlined; '接受中...'; disabled while submitting/previewLoading/preview==null) → _acceptInvite(token). TextButton '输入其他邀请' → clears _pendingInviteToken/_lastPreviewToken/_inviteInputError. _acceptInvite: controller.acceptInvite(token); if no error clear pending state.

PENDING INVITE REMINDER: title '收到家庭邀请'; _InvitePreviewCard(preview). FilledButton.icon '接受邀请' → _acceptPendingInvite (controller.acceptInviteById(preview.inviteId)). TextButton '稍后处理' → adds preview.inviteId to _dismissedInviteIds. _firstPendingInviteReminder: first session.pendingInvitePreviews with non-empty inviteId not in _dismissedInviteIds.

SUB-WIDGETS: _InviteInputSection — card '加入已有家庭', TextField labelText '邀请链接或邀请码' errorText, FilledButton(buttonLabel), hint '已保存邀请，登录后可查看家庭概览' when pendingToken!=null. _InvitePreviewCard — householdName(headlineSmall bold), ownerEmail, '邀请邮箱：{invitedEmail}' when non-empty, Wrap of _InviteMetric pills: '{memberCount} 位成员','{inventoryCount} 个食材','{shoppingCount} 个采购','{customRecipeCount} 个菜谱'. _ErrorText(message in colorScheme.error). _OtpSentText(Row icon mark_email_read_outlined + text). _buildStartupScreen — centered 'Fresh Pantry' + CircularProgressIndicator.

### lib/screens/settings_screen.dart

_"我的" settings hub: profile, stats, household entry, expiry-reminder toggles, backup import/export, dietary-preference chips, nav links._

ConsumerStatefulWidget. build() watches: inventoryProvider.length → inventoryCount, shoppingProvider.length → shoppingCount, customRecipesProvider.length → recipeCount, householdSessionControllerProvider → householdSession, reminderSettingsProvider → reminder, notificationServiceProvider.permissionGranted → permissionGranted. household = first match of selectedHouseholdId in households else first (null if empty). categoryPrefs = household?.categoryPreferences ?? {}. selectedPrefs = keys with value==true. anyReminderOn = remindD1||remindD3||remindD7||remindDaily. permissionMissing = anyReminderOn && !permissionGranted.

LAYOUT (ListView.builder of section widgets, bottom padding AppSpacing.huge): FkTopBar(title '我的', subtitle '设置 · 提醒 · 偏好', onBack maybePop). _ProfileCard(householdName: household?.name ?? '未加入家庭', userEmail: _currentUserEmail). _StatRow with 3 cards: ('食材','$inventoryCount',primary),('采购','$shoppingCount',fkWarn),('收藏菜谱','$recipeCount',fkDanger).

SECTION '家庭共享': _LinkRow(key household_entry_row, label '家庭共享', sub = '未加入家庭' if no households else '{name} · {memberCount} 名成员', icon home_rounded, showBadge = pendingInvitePreviews.isNotEmpty (red dot key household_row_invite_badge), onTap push HouseholdScreen via fkRoute, isLast). If permissionMissing → warning banner (fkWarnSoft bg, icon warning_amber, text '系统通知权限未开启,提醒不会送达。请去 系统设置 → 通知 中允许。').

SECTION '临期提醒' (FkCard padding zero, column of _ToggleRow): '提前 1 天提醒'/'高优先级 · 推送 + 角标'→remindD1; '提前 3 天提醒'/'标准 · 仅推送'→remindD3; '提前 7 天提醒'/'轻量 · 仅角标'→remindD7; '每日 9:00 汇总'/'包含临期 + 库存不足'→remindDaily (isLast). Each onChanged → _onReminderToggle(v, ()=>reminderN.update(remindXX:v)).
_onReminderToggle(newValue, apply): if newValue && !service.permissionGranted → service.requestPermission(); if not granted show info dialog '未开启通知权限' / '系统通知权限未开启,无法发送临期提醒。请在 系统设置 → 通知 中允许。' and RETURN (don't apply); else await apply().

SECTION '数据备份' (FkCard): _ActionRow(key backup_export_action, '导出到剪贴板','复制全部数据为 JSON,粘贴到 Notes/邮箱保存', icon upload_outlined → _onExportTap); Divider; _ActionRow(key backup_import_action, '从剪贴板导入','会覆盖当前所有数据', icon download_outlined, destructive → _onImportTap).
_onExportTap: _withLoading('正在导出数据...', json=backupControllerProvider.export(); Clipboard.setData(json)); fkToast '已复制 {bytes} 字节,粘贴到 Notes/邮箱保存' (bytes = utf8.encode(json).length).
_onImportTap: read clipboard text; empty → info dialog '剪贴板为空'/'请先在另一台设备复制备份 JSON 后再试。'. BackupService.decode(text); catch BackupVersionException → '备份版本不兼容'+e.message; catch FormatException → '备份不是合法 JSON'+e.message. inHousehold = selectedHouseholdIdProvider non-empty. confirmMessage differs (in-household adds a sync-override warning suggesting leaving household first). showAppConfirmDialog(title '确认导入?', confirmLabel '确认覆盖', isDestructive). On confirm: _withLoading('正在导入数据...', backupControllerProvider.import(backup)); catch → '导入出错'/'写入本地数据时失败...'; success → '导入完成'/'数据已恢复。如未刷新，请重启 App。'.

SECTION '饮食偏好' (FkCard padding 14): label '根据偏好为你推荐菜谱'; Wrap of _PrefChip for tags ['高蛋白','低脂','素食','家常菜','快手菜','儿童餐','低碳水']; selected when selectedPrefs.contains(tag); onTap toggles newPrefs[tag]=true/false then householdSessionControllerProvider.notifier.updateCategoryPreferences(household.id, newPrefs) — ONLY if household!=null (no-op in local mode).

SECTION '更多' (FkCard column of _LinkRow): '本周计划'/'规划这周吃什么 · 一键补缺料'(calendar_month_rounded)→MealPlanScreen; '减废成效'/'本月用掉与浪费 · 越用越省'(eco_outlined)→WasteInsightsScreen; '我的食谱'/'添加和管理私房菜单'(menu_book_rounded)→MyRecipesScreen; 'AI 助手'/'配置模型与连接'(auto_awesome_outlined)→AiSettingsScreen; if kDebugMode '验证 Sentry'/'创建一条测试异常'(bug_report_outlined)→_throwSentryTestException (throw StateError); '开源致谢'/'探索菜谱数据来自 HowToCook（Unlicense）'(favorite_outline_rounded)→AlertDialog about HowToCook (Unlicense), isLast.

_currentUserEmail(session): member.email where member.userId==session.currentUserId, else session.email. _withLoading: shows non-dismissible AlertDialog with spinner+message, pops rootNavigator in finally.

SUB-WIDGETS: _ProfileCard (avatar letter = email[0].toUpperCase() or '?'; gradient circle primary→primaryLight; name titleMedium bold + email bodySmall + chevron). _StatRow (Row of FkEntrance-wrapped FkCards). _ToggleRow (label titleSmall + optional sub + Switch: thumb white, track primary/switchTrackOff, transparent outline). _PrefChip (FkPill: selected→primary bg/white text, else surfaceContainer/onSurface). _LinkRow (icon box primarySoft, label+sub, optional red badge dot, chevron). _ActionRow (optional leading icon, destructive→fkDanger color, chevron).

### lib/screens/ai_settings_screen.dart

_OpenAI-compatible AI endpoint config: base URL / API key / model / timeout, with a live connection-test probe and local plaintext persistence._

ConsumerStatefulWidget(testConnection: ConnectionTestFn? injectable for tests). ConnectionTestResult{success:bool, message:String} with .ok()(message '连接成功') and .error(msg). typedef ConnectionTestFn = Future<ConnectionTestResult> Function(AiSettings). defaultTestConnection(settings): probeSettings = settings.copyWith(baseUrl: normalizeAiBaseUrl(baseUrl), timeout: max(timeout, 15s)); AiClient.chat(probeSettings, messages:[AiMessage.text('user','reply with: ok')]); on AiException → error(e.message); on other → error('未知错误: $e').

State: 4 TextEditingControllers _baseUrl/_apiKey/_model/_timeout, bool _testing, bool _saving, ConnectionTestResult? _testResult. initState reads aiSettingsProvider → seeds controllers (_timeout from s.timeout.inSeconds.toString()).
_currentInputs(): AiSettings(baseUrl: normalizeAiBaseUrl(_baseUrl.text), apiKey: _apiKey.text.trim(), model: _model.text.trim(), timeout: Duration(seconds: int.tryParse(_timeout.text.trim()) ?? 60)).
_save(): guards _saving; aiSettingsProvider.notifier.save(_currentInputs()); on done Navigator.pop if canPop.
_runTest(): _testing=true, _testResult=null; fn = widget.testConnection ?? defaultTestConnection; result=await fn(_currentInputs()); setState _testResult.

UI (Scaffold AppBar 'AI 设置', ListView padding lg): TextField key ai_base_url labelText 'Base URL' hintText 'https://cpa.kunish.eu.org/v1' helperText '填写到 /v1 即可；仅填域名也会自动补全'. TextField key ai_api_key labelText 'API Key' obscureText:true. TextField key ai_model labelText 'Model' hintText 'gpt-4o'. TextField key ai_timeout labelText 'Timeout (秒)' keyboardType number. OutlinedButton key ai_test_connection '测试连接' (spinner while _testing) → _runTest. If _testResult!=null show message text (primary if success else error color). FilledButton key ai_save '保存' (spinner while _saving) → _save. Footer text '明文存于本机 SharedPreferences。'.

### lib/screens/household_screen.dart

_Dedicated household-management screen; hosts HouseholdSection and wires every callback to HouseholdSessionController._

ConsumerStatefulWidget. State: _ownerInviteRefreshHouseholdId:String?. build(): watches session; household = match selectedHouseholdId in households else first (null if empty); isOwner = household!=null && household.ownerId==session.currentUserId. _ensureOwnerPendingInvitesLoaded(id,isOwner): if !isOwner clear sentinel; else if sentinel!=id, set sentinel and microtask → controller.refreshOwnerPendingInvites(id) (one-shot per household).

LAYOUT: Scaffold > SafeArea > ListView: FkTopBar(title '家庭', onBack maybePop) + HouseholdSection with these wired props: householdName(=household?.name ?? '未加入家庭'), members(=session.householdMembers or []), isOwner, currentUserId, households, selectedHouseholdId, ownerPendingInvites(=session.ownerPendingInvites), incomingInvites(=session.pendingInvitePreviews). Callbacks (all null when household==null; invite/dissolve also require isOwner): onInviteLink→_onInviteLink, onInviteEmail(email)→_onInviteEmail, onRemoveMember(userId)→_onRemoveMember, onRevokeInvite(inviteId)→_onRevokeInvite, onDissolveHousehold→_onDissolveHousehold, onSwitchHousehold(id)→_onSwitchHousehold, onEditName(newName)→_onEditName, onLeaveHousehold→inline (controller.leaveHousehold; if ok pop), onAcceptInvite(inviteId)→controller.acceptInviteById.

CALLBACKS: _onEditName→controller.updateHouseholdName(id,newName). _onInviteLink→try controller.createInvite(id) (catch → showAppSnackBar error red); then InviteResultSheet.show(inviteUrl) + refreshOwnerPendingInvites. _onInviteEmail→controller.createInvite(id,email:email); InviteResultSheet.show(inviteUrl, invitedEmail:email.trim()) + refresh. _onRemoveMember→controller.removeMember(id,userId); if error snackbar. _onRevokeInvite→confirm dialog '撤销邀请'/'确定撤销该邀请？'(confirm '撤销', destructive); controller.revokeInvite(id,inviteId); error→snackbar. _onDissolveHousehold(id,name)→confirm '解散家庭'/'确定解散「$name」？这会删除家庭、成员、邀请以及所有共享食材、采购和菜谱数据，无法撤销。'(confirm '解散', destructive); clear sentinel; _withLoading('正在解散家庭...', controller.dissolveHousehold(id)); if !dissolved snackbar error; else fkToast '已解散「$name」' + pop if households empty. _onSwitchHousehold(id)→clear sentinel; controller.switchHousehold(id). _withLoading: same non-dismissible spinner dialog pattern as settings.

### lib/household/household_session_controller.dart

_Single source of truth for auth + household session; StateNotifier driving all 4 screens. Wraps a HouseholdGateway (Supabase)._

const supabaseAuthRedirectUrl = 'com.kunish.freshpantry://signin-callback/'. resolveSupabaseAuthRedirectUrl({isWeb,webBaseUri}) → mobile returns the const scheme; web returns origin.

HouseholdSessionState (immutable, copyWith with _preserveError/_preserveInvitePreview sentinels so null can be set explicitly): email='', currentUserId='', selectedHouseholdId='', sentOtpToEmail='', isLoading=true, isSubmitting=false, isPreviewLoading=false, isPendingInvitesLoading=false, isAuthenticated=false, error:String?, households:List<Household>=[], householdMembers:List<HouseholdMember>=[], pendingInvitePreviews:List<HouseholdInvitePreview>=[], ownerPendingInvites:List<OwnerPendingInvite>=[], invitePreview:HouseholdInvitePreview?. Getter selectedHousehold: first household whose id==selectedHouseholdId else null.

HouseholdGateway (interface): authStateChanges:Stream<void>, isAuthenticated:bool, currentUserId:String?, sendOtp(email), verifyEmailOtp(email,token), loadHouseholds, createHousehold(name), uploadInitialData(householdId), createInvite({householdId,email?}):Future<String>, loadHouseholdMembers(id), loadPendingInvites, previewInvite(token), acceptInvite(token), acceptInviteById(inviteId), removeMember({householdId,userId}), revokeInvite(inviteId), dissolveHousehold(id), leaveHousehold(id), fetchOwnerPendingInvites(id), updateHouseholdName(id,name), updateCategoryPreferences(id,prefs).

SupabaseHouseholdGateway: authStateChanges filters onAuthStateChange to {initialSession, signedIn, signedOut}. sendOtp → client.auth.signInWithOtp(email, emailRedirectTo: redirectUrl). verifyEmailOtp(email,token) → try verifyOTP(type: OtpType.email); on AuthException FALL BACK to verifyOTP(type: OtpType.signup) — existing users verify under email-type magic-link code, brand-new signups under signup-type confirmation code; wrong type errors WITHOUT consuming a valid token. uploadInitialData(householdId): loads local inventory/shopping/customRecipes, re-mints non-UUID ids via newSyncEntityId, saveItems to household scope, then deletes the '' (local-only) scope rows, then upserts each to remote.

Controller CONSTRUCTOR subscribes to gateway.authStateChanges → refreshHouseholds() on each event (errors → _setError). int _refreshHouseholdsGeneration guards races.
sendOtp(email): trim; state{email, isSubmitting:true, error:null, sentOtpToEmail:''}; gateway.sendOtp; success → sentOtpToEmail=email isSubmitting:false; catch → error=toString sentOtpToEmail:''.
verifyOtp(token): code=trim, email=state.sentOtpToEmail; if email empty error '请先获取验证码'; if code empty error '请输入验证码'; isSubmitting:true; gateway.verifyEmailOtp(email,code); SUCCESS doesn't flip auth here — the signedIn auth event triggers refreshHouseholds() which sets isAuthenticated; here only clears isSubmitting; catch → error.
refreshHouseholds(): generation guard; isLoading:true; loadHouseholds; selectedId = keep current if still joined else first.id (or '' if empty); load members for selected if authed; sets households/members/selectedId/currentUserId/isAuthenticated; then if authed refreshPendingInvites().
createHousehold(name): trim, empty→error '家庭名称不能为空'; gateway.createHousehold then uploadInitialData(household.id) then load members; sets single-household state isAuthenticated:true.
createInvite(id,{email}): isSubmitting; gateway.createInvite(trimmed email or null) → returns inviteUrl; rethrows on error after setting error.
previewInvite(token): isPreviewLoading; gateway.previewInvite → sets invitePreview; rethrows on error.
refreshPendingInvites({excludeInviteId}): if !authed clears; else loadPendingInvites, optionally filter out excludeInviteId.
acceptInvite(token)/acceptInviteById(inviteId): accept; reload households; selectedId = _selectedHouseholdIdAfterJoin (prefer invite's householdId, else current, else households.last); reload members; remove accepted invite from pending; clear invitePreview; refreshPendingInvites(exclude).
removeMember(id,userId): gateway.removeMember; reload members.
revokeInvite(id,inviteId): gateway.revokeInvite; refreshOwnerPendingInvites(id).
dissolveHousehold(id)/leaveHousehold(id): returns bool; empty id → error '家庭不存在' false; gateway op; reload households; selectedId = _selectedHouseholdIdAfterRemoval (keep current if still present & not removed, else first or ''); reload members; clears ownerPendingInvites; refreshPendingInvites.
refreshOwnerPendingInvites(id): if !authed clears; gateway.fetchOwnerPendingInvites → ownerPendingInvites.
switchHousehold(id): isLoading:true selectedHouseholdId:id; loadHouseholdMembers; on error rolls back selectedHouseholdId to previous; refreshOwnerPendingInvites.
updateHouseholdName(id,name): trim empty→error; gateway.updateHouseholdName; reload households. updateCategoryPreferences(id,prefs): gateway.updateCategoryPreferences; reload households.
Providers: householdGatewayProvider(Provider) builds SupabaseHouseholdGateway(client, remotePantryRepo, inventoryRepo, shoppingRepo, customRecipeRepo). householdSessionControllerProvider = StateNotifierProvider.

### lib/household/household_models.dart

_Domain models for household, member, invite preview, owner pending invite._

Household{id:String, name:String, ownerId:String, defaultStorageArea:String (default 'fridge'), categoryPreferences:Map<String,dynamic>={}}. fromJson keys: id, name, owner_id, default_storage_area(default 'fridge'), category_preferences(Map or {}).
HouseholdMember{householdId:String, userId:String, role:String, email:String}. fromJson keys: household_id, user_id, role(default 'member'), email. Roles seen: 'owner','member'.
HouseholdInvitePreview{inviteId:String='', householdId:String, householdName:String, ownerEmail:String, invitedEmail:String, memberCount:int, inventoryCount:int, shoppingCount:int, customRecipeCount:int, expiresAt:DateTime?}. fromJson keys: invite_id, household_id, household_name, owner_email, invited_email, member_count, inventory_count, shopping_count, custom_recipe_count, expires_at(DateTime.tryParse).
OwnerPendingInvite{id:String, email:String, expiresAt:DateTime, createdAt:DateTime}. fromJson keys: id, email, expires_at(DateTime.parse), created_at(DateTime.parse — these REQUIRE valid dates, unlike preview's tryParse).

### lib/household/invite_token.dart

_Invite-token generation, shape validation, extraction from URLs/raw, and SHA-256 hashing._

_tokenPattern = ^[A-Za-z0-9_-]{10,160}$. generateInviteToken(): 32 chars from alphabet 'A-Za-z0-9_-' using Random.secure(). isInviteTokenShapeValid(token)=_tokenPattern.hasMatch. inviteTokenFromInput(input): trim; if shape-valid return as-is; else Uri.tryParse and extract: (a) schemeless path 'invite/{token}', (b) http/https path 'invite/{token}', (c) scheme com.kunish.freshpantry or freshpantry with host 'invite' single path segment. Returns token only if shape-valid, else null. hashInviteToken(token)=sha256(utf8(token)).toString() hex — what is sent to all preview/accept RPCs (raw token never leaves the device beyond the shared URL).

### lib/sync/remote_pantry_repository.dart

_Supabase data-access for household ops (direct table writes + RPCs) used by the gateway._

SupabaseRemotePantryRepository(client, apiBaseUrl=defaultFreshPantryApiBaseUrl). loadHouseholds(): from('households').select() → Household.fromJson (RLS scopes rows to the user). createHousehold(name): insert households {id:uuid v4, name, owner_id:userId, default_storage_area:'fridge'} then insert household_members {household_id, user_id, role:'owner'}; returns Household.fromJson(row). createInvite({householdId,email?}): generateInviteToken; insert household_invites {household_id, email(null for open), token_hash:hashInviteToken(token), expires_at: now + (email==null ? 24h : 3 days), created_by:userId}; returns '{apiBaseUrl}/invite/{token}'. loadHouseholdMembers(id): rpc('list_household_members', {target_household_id}). loadPendingInvites(): rpc('list_pending_household_invites'). previewInvite(token): validates shape; rpc('preview_household_invite', {invite_token_hash}); takes first row. acceptInvite(token): rpc('accept_household_invite', {invite_token_hash}). acceptInviteById(inviteId): requires UUID; rpc('accept_household_invite_by_id', {target_invite_id}). removeMember({householdId,userId}): both UUID; rpc('remove_household_member', {target_household_id, target_user_id}). leaveHousehold(id): rpc('leave_household', {target_household_id}). revokeInvite(inviteId): rpc('revoke_household_invite', {target_invite_id}). dissolveHousehold(id): rpc('dissolve_household', {target_household_id}). fetchOwnerPendingInvites(id): rpc('list_owner_pending_invites', {target_household_id}). updateHouseholdName(id,name): from('households').update({name}).eq('id',id). updateCategoryPreferences(id,prefs): from('households').update({category_preferences: prefs}).eq('id',id). All RPC ops require currentUser != null (throw StateError otherwise) and UUID-validate ids.

### lib/models/ai_settings.dart + lib/providers/ai_settings_provider.dart + lib/storage/ai_settings_repo.dart + lib/utils/ai_base_url.dart

_AI config model, persistence, and base-URL normalization._

AiSettings{baseUrl:String, apiKey:String, model:String, timeout:Duration=60s}. isConfigured = all three non-empty. toJson keys: baseUrl, apiKey, model, timeoutSeconds. fromJson defaults: '', '', '', 60. static empty = ('','',''). Equality over all 4 fields.
AiSettingsNotifier (Notifier): build() reads aiSettingsRepoProvider.load(); save(next) → repo.save + state=next.
AiSettingsRepo storageKey='ai_settings_v1'; load() decodes JSON via StorageAdapter (returns empty on missing/malformed); save() writes jsonEncode (synchronous, not awaited).
normalizeAiBaseUrl(raw): trim; strip trailing '/'; strip trailing '/chat/completions'; if doesn't end with '/v1' and doesn't contain '/v1/', append '/v1'. Used on input + at AiClient.chat call.

### lib/models/reminder_settings.dart + lib/providers/reminder_settings_provider.dart + lib/storage/reminder_settings_repo.dart

_Expiry-reminder toggle model + persistence; drives notification scheduling._

ReminderSettings{remindD1:bool=true, remindD3:bool=true, remindD7:bool=false, remindDaily:bool=true}. enabledOffsetDays getter = [7 if D7, 3 if D3, 1 if D1] (largest-first, used by ExpiryScheduler). toJson/fromJson keys: remindD1, remindD3, remindD7, remindDaily (defaults true/true/false/true).
ReminderSettingsNotifier: build()→repo.load; set(next)→state=next then repo.save (state set BEFORE persist); update({remindD1,remindD3,remindD7,remindDaily})→set(copyWith).
ReminderSettingsRepo storageKey='reminder_settings_v1'; defensive decode → defaults on missing/malformed.

### lib/providers/backup_controller.dart + lib/services/backup_service.dart

_Backup export/import orchestration (controller) + pure versioned JSON codec (service)._

BackupData{inventory:List<Ingredient>, addHistory:Map<String,dynamic>, shopping:List<ShoppingItem>, customRecipes:List<Recipe>, mealPlan:List<MealPlanEntry>, aiSettings:AiSettings?}. Cache data excluded.
BackupController.export(): builds BackupData from inventoryProvider, inventoryRepo.loadHistory(), shoppingProvider, customRecipesProvider, mealPlanProvider, aiSettingsProvider → BackupService.encode. import(data): replaceFromRemote(rethrowOnError:true) on inventory/shopping/customRecipes/mealPlan notifiers (inbound sync path, NO sync side effects); inventoryRepo.saveHistory(addHistory) + invalidate(addHistoryProvider); if aiSettings!=null save it. Any write failure propagates (settings surfaces it).
BackupService: backupVersion=2. encode → pretty JSON envelope {version:2, exportedAt:ISO8601 UTC now, data:{inventory[],addHistory{},shopping[],customRecipes[],mealPlan[], aiSettings? }}. decode(json): throws FormatException for non-JSON/non-object root or wrong shapes; BackupVersionException for missing/non-int version or version != 2. Parses lists via whereType<Map>+fromJson; addHistory as raw map; aiSettings optional. Decode happens fully before any write so a bad blob can't partially overwrite.

### lib/widgets/household/household_section.dart

_Reusable household management UI block hosted by HouseholdScreen._

HouseholdSection props (all callbacks nullable): householdName, members:List<HouseholdMember>, onInvite/onInviteLink:Future Fn/onInviteEmail:Future Fn(email), isOwner, currentUserId, onRemoveMember:Fn(userId), ownerPendingInvites:List<OwnerPendingInvite>, onRevokeInvite:Fn(inviteId), onDissolveHousehold:Fn, households:List<Household>, selectedHouseholdId, onSwitchHousehold:ValueChanged<String>, onEditName:Fn(newName), onLeaveHousehold:Fn, incomingInvites:List<HouseholdInvitePreview>, onAcceptInvite:Fn(inviteId). canInvite=isOwner&&(any invite cb). canDissolve=isOwner&&onDissolveHousehold!=null. canLeave=!isOwner&&onLeaveHousehold!=null.
LAYOUT: FkSectionHead('家庭共享', count:members.length). Card: header row with home icon; if households.length>1 && onSwitchHousehold → DropdownButton<String> of household names (value=selectedHouseholdId or first); else plain name text; if isOwner&&onEditName → edit IconButton → _EditNameDialog. If incomingInvites non-empty && onAcceptInvite → '收到的邀请' header + _IncomingInviteRow each (householdName + '来自 {ownerEmail} · {inventoryCount} 项库存 · {memberCount} 名成员' + '接受' FilledButton). Members: '登录后会显示家庭成员' when empty else _buildMemberRow each. Owner pending: if isOwner&&ownerPendingInvites non-empty → '待处理邀请' + _PendingInviteRow each (email or '扫码/链接邀请', '待接受', close IconButton → onRevoke). canInvite → _InviteActions (FilledButton '扫码/链接邀请' icon qr_code_2 → onInviteLink; OutlinedButton '邮箱定向邀请' icon mail_outline → _InviteMemberDialog). canDissolve → Divider + TextButton.icon '解散家庭' (delete_forever, fkDanger). canLeave → Divider + TextButton.icon '退出家庭' (logout) → _confirmLeave (confirm '退出家庭'/'退出后将不再看到该家庭的共享数据。确定退出？').
_buildMemberRow: canRemove = isOwner && member.userId!=currentUserId && member.role!='owner' && onRemoveMember!=null; if removable wraps in Dismissible (endToStart, red delete bg, confirmDismiss → '移除成员'/'确定移除 {email}？'). _MemberRow: account icon + email + FkPill (role=='owner'?'拥有者':'成员'). _InviteMemberDialog: '邮箱定向邀请', email TextField (validates non-empty '请输入成员邮箱', shows error on submit failure), '发送邀请'. _EditNameDialog: '编辑家庭名称', name TextField (non-empty '家庭名称不能为空'), '保存'.

### lib/widgets/settings/invite_result_sheet.dart

_Bottom sheet shown after creating an invite: QR code + copyable link + share actions._

InviteResultSheet(inviteUrl:String, invitedEmail:String=''). static show() → showModalBottomSheet (isScrollControlled, surface bg, top-rounded AppRadius.xl). UI: drag handle; '邀请链接已创建'; subtitle = invitedEmail or '分享链接或二维码，家人登录后即可加入'; QrImageView(data:inviteUrl, version auto, size 200, white bg) inside RepaintBoundary(_qrBoundaryKey); SelectableText of inviteUrl; FilledButton '复制链接' (Clipboard + pop + fkToast '邀请链接已复制'); OutlinedButton '分享链接' (SharePlus '加入我的家庭: {url}' subject '家庭邀请'); OutlinedButton '分享二维码' (renders boundary to PNG pixelRatio 3, shares XFile 'fresh-pantry-invite.png' with text '扫码加入我的家庭：{url}'). Uses qr_flutter + share_plus.

### lib/services/invite_link_service.dart + lib/providers/invite_link_provider.dart

_Deep-link invite source abstraction (app_links) and its provider._

InviteLinkSource{incomingLinks:Stream<String>, consumeInitialLink():Future<String?>}. AppLinksInviteLinkSource wraps app_links AppLinks (uriLinkStream.map(toString), getInitialLink). InMemoryInviteLinkSource (test). NoOpInviteLinkSource (const, empty stream/null) is the DEFAULT bound in inviteLinkSourceProvider — overridden in main.dart for real deep-link handling. createInviteLinkSource() returns AppLinksInviteLinkSource. AuthGateScreen reads inviteLinkSourceProvider to capture inbound invite URLs.

### lib/sync/sync_providers.dart

_Root-resident active-household id projection target consumed by all sync notifiers._

selectedHouseholdIdStateProvider = StateProvider<String>('') — MUST be root-resident (a nested ProviderScope override never reaches root-stored inventory/shopping/recipe notifiers; their enqueueSync would read the root default '', no-op, and changes never sync). selectedHouseholdIdProvider = Provider reading the state provider (read seam for tests). AuthGateScreen writes this from a ref.listen on session's active household. Settings reads selectedHouseholdIdProvider to detect in-household state during import.

### lib/config/backend_config.dart

_Backend connection config (Supabase + invite API base)._

defaultFreshPantryApiBaseUrl = 'https://api.fresh-pantry.kunish.eu.org'. BackendConfig{supabaseUrl, supabasePublishableKey, apiBaseUrl}. fromEnvironment reads SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, FRESH_PANTRY_API_BASE_URL (default = const). validate() requires non-empty supabaseUrl (valid http/https), non-empty publishable key, valid apiBaseUrl. apiBaseUrl is the host prefix for invite links '{apiBaseUrl}/invite/{token}'.

## 外部集成

- Supabase Auth (email OTP): signInWithOtp(email, emailRedirectTo: 'com.kunish.freshpantry://signin-callback/') sends a 6-digit code; verifyOTP(email, token, type: OtpType.email) with fallback to OtpType.signup for brand-new users. Auth state observed via onAuthStateChange filtered to {initialSession, signedIn, signedOut}. No PKCE/magic-link code exchange (deliberately moved off it — the link's code reached the app but was never exchanged).
- Supabase Postgres tables (direct PostgREST): households (id uuid PK, name, owner_id uuid, default_storage_area default 'fridge', category_preferences jsonb); household_members (household_id, user_id, role text 'owner'|'member'); household_invites (household_id, email nullable, token_hash text = sha256(token), expires_at timestamptz, created_by uuid). RLS scopes selects to the current user. Direct writes: insert households+household_members on create; insert household_invites on createInvite; update households.name and households.category_preferences.
- Supabase RPC functions (Postgres): list_household_members(target_household_id), list_pending_household_invites(), preview_household_invite(invite_token_hash), accept_household_invite(invite_token_hash), accept_household_invite_by_id(target_invite_id), remove_household_member(target_household_id, target_user_id), leave_household(target_household_id), revoke_household_invite(target_invite_id), dissolve_household(target_household_id), list_owner_pending_invites(target_household_id). All take the SHA-256 token hash, never the raw token.
- Invite-link web/deep-link API: host 'https://api.fresh-pantry.kunish.eu.org', invite URL format '{apiBaseUrl}/invite/{token}'. Deep-link schemes accepted on inbound: http(s)://.../invite/{token}, com.kunish.freshpantry://invite/{token}, freshpantry://invite/{token} (via app_links uriLinkStream + getInitialLink).
- OpenAI-compatible Chat Completions API (AI settings test + AI features): POST {baseUrl}/chat/completions, header Authorization: Bearer {apiKey}, body {model, messages, temperature:0.2, response_format?}; baseUrl normalized to end with /v1. Used by AiSettingsScreen's '测试连接' probe (sends 'reply with: ok', min 15s timeout).
- flutter_local_notifications + timezone (current; to be replaced by UserNotifications): NotificationService.permissionGranted / requestPermission() (iOS requestPermissions alert+badge+sound) gate the reminder toggles in Settings. Daily 9:00 summary + per-item D-1/D-3/D-7 reminders.
- Clipboard (backup export/import) — export copies pretty JSON to clipboard; import reads clipboard text and decodes BackupService v2.
- share_plus + qr_flutter (InviteResultSheet) — share invite link text and a rendered QR PNG.

## Swift 映射

Architecture: one @Observable HouseholdSessionModel (actor-isolated async methods or @MainActor) replacing HouseholdSessionController/State — exposes the same fields (email, currentUserId, selectedHouseholdId, sentOtpToEmail, isLoading/isSubmitting/isPreviewLoading/isPendingInvitesLoading/isAuthenticated, error, households, householdMembers, pendingInvitePreviews, ownerPendingInvites, invitePreview) and methods (sendOtp, verifyOtp, refreshHouseholds, createHousehold, createInvite, previewInvite, refreshPendingInvites, acceptInvite, acceptInviteById, removeMember, revokeInvite, dissolveHousehold, leaveHousehold, refreshOwnerPendingInvites, switchHousehold, updateHouseholdName, updateCategoryPreferences). Inject a HouseholdGateway protocol implemented over the Supabase Swift SDK (auth.signInWithOTP / verifyOTP(email:token:type:), .from('...').select/insert/update, .rpc(...)). Use Supabase Swift's authStateChanges AsyncStream filtered to initialSession/signedIn/signedOut, .task{ for await ... } in the gate view → refreshHouseholds.\n\nScreens (SwiftUI): AuthGateView replaces AuthGateScreen — a switch over the model driving LoginView / HouseholdBootstrapView / InvitePreviewView / PendingInviteReminderView / authenticated TabView, with the same routing precedence. SettingsView, AiSettingsView, HouseholdView as SwiftUI screens. Use TextField with .keyboardType / .textContentType(.oneTimeCode) and .textContentType(.username/.emailAddress) for autofill; @FocusState for submit-on-return.\n\nPersistence: ReminderSettings and AiSettings are small key-value blobs — use a Codable struct in UserDefaults (or a tiny SwiftData @Model) keyed 'reminder_settings_v1' / 'ai_settings_v1' to preserve forward-compat; keep enabledOffsetDays + isConfigured as computed props. Backup remains a versioned JSON codec (BackupService, version 2 envelope {version, exportedAt, data}) using Codable; export to UIPasteboard, import from clipboard with the same confirm/decode-before-write ordering and replaceFromRemote-equivalent SwiftData writes (no sync side effects). Active-household id: an observable property on a root environment object (the SwiftUI equivalent of the root-resident selectedHouseholdIdStateProvider) so the SwiftData/Supabase sync layer reads the right household.\n\nNotifications: NotificationService → UNUserNotificationCenter wrapper; requestPermission via requestAuthorization([.alert,.badge,.sound]); permission-missing banner from getNotificationSettings. Daily 9:00 + D-N reminders via UNCalendarNotificationTrigger / BGTaskScheduler for background refresh.\n\nDeep links / invites: invite token logic (generate 32-char A-Za-z0-9_-, validate regex ^[A-Za-z0-9_-]{10,160}$, extract from http(s)/custom-scheme URLs, SHA-256 hash via CryptoKit SHA256) is a pure Swift utility. Handle inbound links via onOpenURL / Universal Links + URL scheme registration (com.kunish.freshpantry, freshpantry). InviteResultSheet → a SwiftUI sheet with a QR code (CoreImage CIFilter.qrCodeGenerator), copy button (UIPasteboard), and ShareLink. Crypto: import CryptoKit, SHA256.hash(data: Data(token.utf8)) hex.\n\nAI test probe: a ConnectionTester protocol (injectable) calling the OpenAI-compatible endpoint via URLSession; reuse the same normalizeAiBaseUrl logic (trim, strip trailing slash + /chat/completions, ensure /v1).

## 迁移注意

PARITY-CRITICAL INVARIANTS: (1) verifyOTP dual-type fallback — try OtpType.email first, on AuthException retry with OtpType.signup. Existing users get email-type codes, brand-new signups get signup-type confirmation codes; a wrong-type attempt errors WITHOUT consuming a valid token, so the fallback is safe and REQUIRED or new-user login breaks. (2) verifyOtp success must NOT itself flip isAuthenticated — the signedIn auth event triggers refreshHouseholds() which flips it; verifyOtp only clears isSubmitting. Preserve this event-driven flow or the gate won't advance. (3) sentOtpToEmail gates the two-stage login UI (empty=show 'send code', set=show OTP entry); verifyOtp errors '请先获取验证码' if it's empty. (4) Active-household projection MUST be root-resident: a nested override never reaches root-stored sync notifiers → adds silently don't sync ('对方看不到'). In SwiftUI this means the active-household property lives on a single shared root environment object consumed by the sync layer. (5) All invite RPCs send hashInviteToken(token) (SHA-256 hex), never the raw token; the raw token only appears in the shared invite URL. (6) Invite expiry windows: open (email-less) link = 24h, email-bound = 3 days (server-enforced; mirror when minting). (7) createHousehold ordering: insert household → insert owner member → uploadInitialData (re-mint non-UUID ids, save to household scope, DELETE '' local-only scope rows to avoid duplicate orphans, upsert to remote). The '' scope purge after adoption is essential to avoid orphan re-minting. (8) Backup: decode FULLY before any write (FormatException / BackupVersionException mapped to specific dialogs) so a bad blob can't partially overwrite; version is hard-pinned to 2; addHistory round-trips as a raw map (no model). Imports use the inbound sync path with NO sync side effects, and propagate write failures (no false 'success'). In-household import shows an extra warning that cloud sync may overwrite imported data (suggest leaving household first). (9) Member removal eligibility: isOwner && target != currentUser && role != 'owner'. (10) selectedHouseholdId resolution helpers: after join prefer the invite's householdId then current then households.last; after removal keep current if still present & not the removed one, else first or ''. (11) OwnerPendingInvite.fromJson uses DateTime.parse (throws on bad/missing dates) vs HouseholdInvitePreview.expires_at uses tryParse (nullable) — keep the strictness difference. (12) dietary-preference chips are a no-op in local-only mode (household==null); they persist to households.category_preferences jsonb (value true=selected) only when in a household. (13) Reminder toggle turning ON triggers a notification-permission request; if denied, the toggle does NOT apply (and a settings-prompt dialog shows). Daily summary fires at 09:00. (14) AiSettings stored as plaintext locally (screen explicitly states this); timeout test probe forces a min 15s.

## 开放问题

- The Supabase RPC function bodies (list_household_members, accept_household_invite, dissolve_household, etc.) and the household_invites table schema/RLS live server-side and were not read — exact returned columns, permission checks, and cascade-delete behavior for dissolve must be confirmed from the Supabase migrations (apps/ ... /supabase) before relying on them for parity.
- Household.defaultStorageArea is always set to 'fridge' on create and read from default_storage_area, but no code in this subsystem lets the user change it — confirm whether any other screen edits it or it's effectively a constant.
- category_preferences is typed Map<String,dynamic> but the UI only ever writes bool values keyed by the 7 dietary tags; confirm no other writer stores non-bool/non-tag keys (Swift would model it as [String: Bool]).
- The reminder toggles persist locally only (reminder_settings_v1); whether/how they trigger actual notification (re)scheduling is owned by ExpiryScheduler (not in this subsystem) — the scheduling trigger points must be traced separately.
- NoOpInviteLinkSource is the default provider value; the real AppLinks override is wired in main.dart (not read here) — confirm the exact deep-link registration and any Universal Links domain config when porting to onOpenURL.
- supabaseAuthRedirectUrl 'com.kunish.freshpantry://signin-callback/' is passed to signInWithOtp but, per code comments, the deep-link round-trip is intentionally unused for OTP code entry — confirm whether the redirect/callback is still needed for any other auth flow before dropping it in Swift.
