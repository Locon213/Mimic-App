import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../providers/vpn_provider.dart';
import '../../utils/app_theme.dart';

/// Connection Tile - Large connect button with status indicator
class ConnectionTile extends StatelessWidget {
  final VoidCallback onConnectPressed;
  final VoidCallback onDisconnectPressed;

  const ConnectionTile({
    super.key,
    required this.onConnectPressed,
    required this.onDisconnectPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<VpnProvider>(
      builder: (context, vpnProvider, child) {
        final isConnected = vpnProvider.isConnected;
        final isConnecting = vpnProvider.isConnecting;

        return Container(
          decoration: BoxDecoration(
            gradient: isConnected
                ? AppColors.connectedGradient
                : isConnecting
                    ? LinearGradient(
                        colors: [
                          AppColors.warning.withOpacity(0.8),
                          AppColors.warning,
                        ],
                      )
                    : AppColors.disconnectedGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: (isConnected
                        ? AppColors.connected
                        : isConnecting
                            ? AppColors.warning
                            : AppColors.disconnected)
                    .withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isConnected ? onDisconnectPressed : onConnectPressed,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 50),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status Icon
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: isConnecting
                          ? SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Icon(
                              isConnected
                                  ? Icons.power_off_rounded
                                  : Icons.play_arrow_rounded,
                              size: 40,
                              color: Colors.white,
                            ),
                    )
                        .animate()
                        .scale(
                          duration: 300.ms,
                          curve: Curves.easeOutBack,
                        )
                        .then()
                        .shimmer(
                          duration: 2000.ms,
                          color: Colors.white.withOpacity(0.3),
                        ),

                    const SizedBox(height: 24),

                    // Status Text
                    Text(
                      vpnProvider.status.label,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Server Name (when connected)
                    if (vpnProvider.currentServer != null)
                      Text(
                        vpnProvider.currentServer!.displayName,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Action Button Text
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isConnected ? 'TAP TO DISCONNECT' : 'TAP TO CONNECT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.9),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
