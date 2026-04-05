import 'package:flutter/material.dart';

/// 현재 빌드 환경 정보를 표시하는 화면.
///
/// Flavor, App Name, Firebase 연결 상태, Firebase Project ID를
/// 카드 형태로 표시한다.
/// 개발/QA 환경에서 현재 빌드 환경을 확인하는 용도이다.
class EnvironmentInfoScreen extends StatelessWidget {
  /// 환경 정보 화면을 생성한다.
  const EnvironmentInfoScreen({
    required this.isFirebaseInitialized,
    super.key,
  });

  /// Firebase 초기화 성공 여부.
  final bool isFirebaseInitialized;

  @override
  Widget build(BuildContext context) {
    const flavor = String.fromEnvironment('flavor', defaultValue: 'dev');
    const appName = String.fromEnvironment(
      'appName',
      defaultValue: 'StarterKit',
    );
    const firebaseProjectId = String.fromEnvironment(
      'firebaseProjectId',
      defaultValue: '-',
    );

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Environment Info'),
        backgroundColor: theme.colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _EnvironmentCard(
            icon: Icons.layers,
            label: 'Flavor',
            value: flavor.toUpperCase(),
          ),
          const SizedBox(height: 12),
          const _EnvironmentCard(
            icon: Icons.app_settings_alt,
            label: 'App Name',
            value: appName,
          ),
          const SizedBox(height: 12),
          _EnvironmentCard(
            icon: isFirebaseInitialized ? Icons.cloud_done : Icons.cloud_off,
            label: 'Firebase',
            value: isFirebaseInitialized ? 'Connected' : 'Not Connected',
            valueColor: isFirebaseInitialized ? Colors.green : Colors.orange,
          ),
          const SizedBox(height: 12),
          const _EnvironmentCard(
            icon: Icons.folder,
            label: 'Firebase Project ID',
            value: firebaseProjectId,
          ),
        ],
      ),
    );
  }
}

class _EnvironmentCard extends StatelessWidget {
  const _EnvironmentCard({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: valueColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
