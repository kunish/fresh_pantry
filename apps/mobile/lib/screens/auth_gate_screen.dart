import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../household/household_session_controller.dart';
import '../sync/sync_providers.dart';
import '../theme/app_theme.dart';

class AuthGateScreen extends ConsumerStatefulWidget {
  const AuthGateScreen({super.key, required this.authenticatedChild});

  final Widget authenticatedChild;

  @override
  ConsumerState<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends ConsumerState<AuthGateScreen> {
  final _emailController = TextEditingController();
  final _householdNameController = TextEditingController(text: '我的家庭');

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      ref.read(householdSessionControllerProvider.notifier).refreshHouseholds();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _householdNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(householdSessionControllerProvider);

    if (session.households.isNotEmpty) {
      return ProviderScope(
        overrides: [
          selectedHouseholdIdProvider.overrideWithValue(
            session.households.first.id,
          ),
        ],
        child: widget.authenticatedChild,
      );
    }

    if (session.isLoading) {
      return _buildStartupScreen(context);
    }

    if (session.isAuthenticated) {
      return _buildHouseholdBootstrap(context, session);
    }

    return _buildLoginForm(context, session);
  }

  Widget _buildStartupScreen(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Fresh Pantry',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context, HouseholdSessionState session) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '登录 Fresh Pantry',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    TextField(
                      controller: _emailController,
                      enabled: !session.isSubmitting,
                      autofillHints: const [AutofillHints.email],
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(labelText: '邮箱'),
                      onSubmitted: (_) => _sendOtp(),
                    ),
                    if (session.error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _ErrorText(session.error!),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton.icon(
                      onPressed: session.isSubmitting ? null : _sendOtp,
                      icon: session.isSubmitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.mail_outline),
                      label: Text(session.isSubmitting ? '发送中...' : '发送登录链接'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHouseholdBootstrap(
    BuildContext context,
    HouseholdSessionState session,
  ) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '创建家庭配置',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    '首次登录后需要创建一个家庭，之后可以在设置里邀请家人加入。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  TextField(
                    controller: _householdNameController,
                    enabled: !session.isSubmitting,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(labelText: '家庭名称'),
                    onSubmitted: (_) => _createHousehold(),
                  ),
                  if (session.error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ErrorText(session.error!),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: session.isSubmitting ? null : _createHousehold,
                    icon: session.isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.home_outlined),
                    label: Text(session.isSubmitting ? '创建中...' : '创建家庭'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _sendOtp() {
    ref
        .read(householdSessionControllerProvider.notifier)
        .sendOtp(_emailController.text);
  }

  void _createHousehold() {
    ref
        .read(householdSessionControllerProvider.notifier)
        .createHousehold(_householdNameController.text);
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    );
  }
}
