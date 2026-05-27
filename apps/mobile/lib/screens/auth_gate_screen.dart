import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../household/household_session_controller.dart';
import '../theme/app_theme.dart';

class AuthGateScreen extends ConsumerStatefulWidget {
  const AuthGateScreen({super.key, required this.authenticatedChild});

  final Widget authenticatedChild;

  @override
  ConsumerState<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends ConsumerState<AuthGateScreen> {
  final _emailController = TextEditingController();

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(householdSessionControllerProvider);

    if (session.households.isNotEmpty) {
      return widget.authenticatedChild;
    }

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
                      Text(
                        session.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
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

  void _sendOtp() {
    ref
        .read(householdSessionControllerProvider.notifier)
        .sendOtp(_emailController.text);
  }
}
