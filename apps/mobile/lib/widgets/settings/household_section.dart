import 'package:flutter/material.dart';

import '../../household/household_models.dart';
import '../../theme/app_theme.dart';
import '../shared/fk_card.dart';
import '../shared/fk_pill.dart';
import '../shared/fk_section_head.dart';

class HouseholdSection extends StatelessWidget {
  const HouseholdSection({
    super.key,
    required this.householdName,
    required this.members,
    this.onInvite,
    this.onInviteEmail,
  });

  final String householdName;
  final List<HouseholdMember> members;
  final VoidCallback? onInvite;
  final Future<void> Function(String email)? onInviteEmail;

  @override
  Widget build(BuildContext context) {
    final inviteAction = onInviteEmail == null
        ? onInvite
        : () => _showInviteDialog(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FkSectionHead(title: '家庭共享', count: members.length),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: FkCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppColors.primarySoft,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.home_rounded,
                        color: AppColors.primaryContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        householdName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (members.isEmpty)
                  Text(
                    '登录后会显示家庭成员',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  )
                else
                  for (final member in members) _MemberRow(member: member),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: inviteAction,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('邀请成员'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showInviteDialog(BuildContext context) {
    final onSubmit = onInviteEmail;
    if (onSubmit == null) return Future<void>.value();
    return showDialog<void>(
      context: context,
      builder: (_) => _InviteMemberDialog(onSubmit: onSubmit),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});

  final HouseholdMember member;

  @override
  Widget build(BuildContext context) {
    final label = member.role == 'owner' ? '拥有者' : '成员';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(
            Icons.account_circle_outlined,
            color: AppColors.outline,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              member.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          FkPill(label: label, sm: true),
        ],
      ),
    );
  }
}

class _InviteMemberDialog extends StatefulWidget {
  const _InviteMemberDialog({required this.onSubmit});

  final Future<void> Function(String email) onSubmit;

  @override
  State<_InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<_InviteMemberDialog> {
  final _controller = TextEditingController();
  var _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.trim().isEmpty) {
      setState(() => _error = '请输入成员邮箱');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_controller.text);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('邀请成员'),
      content: TextField(
        controller: _controller,
        enabled: !_isSubmitting,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(labelText: '成员邮箱', errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: const Text('发送邀请'),
        ),
      ],
    );
  }
}
