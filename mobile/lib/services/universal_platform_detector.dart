import 'package:flutter/material.dart';

enum SocialPlatform { threads, tiktok, instagram, x, pinterest, facebook, snapchat, youtube, unknown }

class PlatformMatch {
  final SocialPlatform platform;
  final String hostname;
  final String normalizedUrl;

  const PlatformMatch({
    required this.platform,
    required this.hostname,
    required this.normalizedUrl,
  });

  bool get isSupported => platform != SocialPlatform.unknown;
  bool get isThreads => platform == SocialPlatform.threads;

  String get label {
    switch (platform) {
      case SocialPlatform.threads:
        return 'Threads';
      case SocialPlatform.tiktok:
        return 'TikTok';
      case SocialPlatform.instagram:
        return 'Instagram';
      case SocialPlatform.x:
        return 'X/Twitter';
      case SocialPlatform.pinterest:
        return 'Pinterest';
      case SocialPlatform.facebook:
        return 'Facebook';
      case SocialPlatform.snapchat:
        return 'Snapchat';
      case SocialPlatform.youtube:
        return 'YouTube';
      case SocialPlatform.unknown:
        return 'Unsupported';
    }
  }

  IconData get icon {
    switch (platform) {
      case SocialPlatform.threads:
        return Icons.alternate_email_rounded;
      case SocialPlatform.tiktok:
        return Icons.music_video_rounded;
      case SocialPlatform.instagram:
        return Icons.camera_alt_rounded;
      case SocialPlatform.x:
        return Icons.close_rounded;
      case SocialPlatform.pinterest:
        return Icons.push_pin_rounded;
      case SocialPlatform.facebook:
        return Icons.public_rounded;
      case SocialPlatform.snapchat:
        return Icons.flash_on_rounded;
      case SocialPlatform.youtube:
        return Icons.play_circle_fill_rounded;
      case SocialPlatform.unknown:
        return Icons.help_outline_rounded;
    }
  }

  Color get accent {
    switch (platform) {
      case SocialPlatform.threads:
        return Colors.white;
      case SocialPlatform.tiktok:
        return const Color(0xFF00F2EA);
      case SocialPlatform.instagram:
        return const Color(0xFFD62976);
      case SocialPlatform.x:
        return const Color(0xFFE5E7EB);
      case SocialPlatform.pinterest:
        return const Color(0xFFE60023);
      case SocialPlatform.facebook:
        return const Color(0xFF1877F2);
      case SocialPlatform.snapchat:
        return const Color(0xFFFFFC00);
      case SocialPlatform.youtube:
        return const Color(0xFFFF0033);
      case SocialPlatform.unknown:
        return const Color(0xFFF0A8A8);
    }
  }
}

class UniversalPlatformDetector {
  static const supportedLabel = 'Threads, TikTok, Instagram, X/Twitter, Pinterest, Facebook, Snapchat, and YouTube';

  static PlatformMatch detect(String raw) {
    final value = raw.trim();
    final uri = Uri.tryParse(value);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null || (scheme != 'http' && scheme != 'https')) {
      return PlatformMatch(platform: SocialPlatform.unknown, hostname: '', normalizedUrl: value);
    }

    var host = uri.host.toLowerCase();
    if (host.startsWith('www.')) host = host.substring(4);

    SocialPlatform platform = SocialPlatform.unknown;
    if (_matches(host, const ['threads.com', 'threads.net'])) {
      platform = SocialPlatform.threads;
    } else if (_matches(host, const ['tiktok.com', 'm.tiktok.com', 'vm.tiktok.com', 'vt.tiktok.com'])) {
      platform = SocialPlatform.tiktok;
    } else if (_matches(host, const ['instagram.com', 'instagr.am'])) {
      platform = SocialPlatform.instagram;
    } else if (_matches(host, const ['x.com', 'twitter.com', 'mobile.twitter.com'])) {
      platform = SocialPlatform.x;
    } else if (_matches(host, const ['pinterest.com', 'pin.it'])) {
      platform = SocialPlatform.pinterest;
    } else if (_matches(host, const ['facebook.com', 'm.facebook.com', 'fb.watch'])) {
      platform = SocialPlatform.facebook;
    } else if (_matches(host, const ['snapchat.com', 'story.snapchat.com'])) {
      platform = SocialPlatform.snapchat;
    } else if (_matches(host, const ['youtube.com', 'm.youtube.com', 'youtu.be'])) {
      platform = SocialPlatform.youtube;
    }

    return PlatformMatch(platform: platform, hostname: host, normalizedUrl: value);
  }

  static List<PlatformMatch> detectAll(Iterable<String> urls) => urls.map(detect).toList(growable: false);

  static bool _matches(String host, List<String> allowed) {
    return allowed.any((item) => host == item || host.endsWith('.$item'));
  }
}
