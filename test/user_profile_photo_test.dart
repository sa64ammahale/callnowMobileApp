import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:callnow_new/model/user_profile.dart';
import 'package:callnow_new/services/config_service.dart';
import 'package:callnow_new/screens/profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'base_url': 'http://192.168.1.100/callnowCRM/api/v1',
    });
    await ConfigService.init();
  });

  group('UserProfile Photo Reference Tests', () {
    test('automatically maps complete photo references from server payload', () {
      final json = {
        'id': 1,
        'name': 'Telecaller',
        'email': 'telecaller@callnow.com',
        'mobile': '9876543210',
        'profile_photo': 'user_1_1793685393.jpg',
        'profile_photo_url': 'http://192.168.1.100/callnowCRM/uploads/profile_photos/user_1_1793685393.jpg',
        'avatar_url': 'http://192.168.1.100/callnowCRM/uploads/profile_photos/user_1_1793685393.jpg',
        'profile_picture': 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ...',
        'profile_picture_url': 'http://192.168.1.100/callnowCRM/uploads/profile_photos/user_1_1793685393.jpg',
      };

      final profile = UserProfile.fromJson(json);

      expect(profile.id, equals(1));
      expect(profile.name, equals('Telecaller'));
      expect(profile.email, equals('telecaller@callnow.com'));
      expect(profile.mobile, equals('9876543210'));
      expect(profile.profilePhoto, equals('user_1_1793685393.jpg'));
      expect(profile.profilePhotoUrl, equals('http://192.168.1.100/callnowCRM/uploads/profile_photos/user_1_1793685393.jpg'));
      expect(profile.avatarUrl, equals('http://192.168.1.100/callnowCRM/uploads/profile_photos/user_1_1793685393.jpg'));
      expect(profile.profilePicture, equals('data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ...'));
      expect(profile.profilePictureUrl, equals('http://192.168.1.100/callnowCRM/uploads/profile_photos/user_1_1793685393.jpg'));
    });

    test('falls back to avatar_url or profile_picture_url if profile_photo_url is absent', () {
      final json = {
        'id': 2,
        'name': 'Agent Smith',
        'email': 'smith@callnow.com',
        'avatar_url': 'https://callnow.increditsolutions.in/uploads/profile_photos/smith.png',
      };

      final profile = UserProfile.fromJson(json);
      expect(profile.profilePhotoUrl, equals('https://callnow.increditsolutions.in/uploads/profile_photos/smith.png'));
      expect(profile.avatarUrl, equals('https://callnow.increditsolutions.in/uploads/profile_photos/smith.png'));
    });

    test('normalizes relative photo path using ConfigService.baseUrl', () {
      final json = {
        'id': 3,
        'name': 'Relative Tester',
        'profile_photo_url': '/callnowCRM/uploads/profile_photos/relative.jpg',
      };

      final profile = UserProfile.fromJson(json);
      expect(profile.profilePhotoUrl, contains('http://192.168.1.100/callnowCRM/uploads/profile_photos/relative.jpg'));
    });

    test('rewrites localhost/127.0.0.1 in photo url to ConfigService.baseUrl host', () {
      final json = {
        'id': 4,
        'name': 'Localhost Tester',
        'profile_photo_url': 'http://localhost/callnowCRM/uploads/profile_photos/photo.jpg',
      };

      final profile = UserProfile.fromJson(json);
      // Rewritten to match baseUrl host 192.168.1.100 so mobile devices can access it
      expect(profile.profilePhotoUrl, equals('http://192.168.1.100/callnowCRM/uploads/profile_photos/photo.jpg'));
    });

    test('avatarImageProvider creates NetworkImage for web URLs and MemoryImage for base64 data URIs', () {
      // 1. Network URL
      final webProfile = UserProfile.fromJson({
        'id': 5,
        'name': 'Web User',
        'profile_photo_url': 'https://example.com/avatar.jpg',
      });
      final netProvider = webProfile.avatarImageProvider;
      expect(netProvider, isA<NetworkImage>());
      expect((netProvider as NetworkImage).url, equals('https://example.com/avatar.jpg'));

      // 2. Base64 1x1 transparent PNG data URI
      const base64Png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';
      final base64Profile = UserProfile.fromJson({
        'id': 6,
        'name': 'Base64 User',
        'profile_picture': base64Png,
      });
      final memProvider = base64Profile.avatarImageProvider;
      expect(memProvider, isA<MemoryImage>());
      expect((memProvider as MemoryImage).bytes.isNotEmpty, isTrue);
    });

    test('toJson preserves all photo reference fields', () {
      final profile = UserProfile(
        id: 7,
        name: 'Json Agent',
        username: 'json.agent',
        email: 'json@callnow.com',
        mobile: '1234567890',
        role: 'TELECALLER',
        companyName: 'CallNow CRM',
        teamName: 'General',
        department: 'Operations',
        joinDate: '2026-01-01',
        profilePhoto: 'agent_7.jpg',
        profilePhotoUrl: 'https://callnow.com/photos/agent_7.jpg',
        avatarUrl: 'https://callnow.com/photos/agent_7.jpg',
        profilePicture: 'data:image/jpeg;base64,abc123',
        profilePictureUrl: 'https://callnow.com/photos/agent_7.jpg',
      );

      final map = profile.toJson();
      expect(map['profile_photo'], equals('agent_7.jpg'));
      expect(map['profile_photo_url'], equals('https://callnow.com/photos/agent_7.jpg'));
      expect(map['avatar_url'], equals('https://callnow.com/photos/agent_7.jpg'));
      expect(map['profile_picture'], equals('data:image/jpeg;base64,abc123'));
      expect(map['profile_picture_url'], equals('https://callnow.com/photos/agent_7.jpg'));
    });
  });

  group('ProfileScreen CircleAvatar with Profile Photo Test', () {
    testWidgets('renders CircleAvatar using NetworkImage when profilePhotoUrl is present', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final userPayload = {
        'id': 1,
        'name': 'Telecaller Photo User',
        'email': 'telecaller@callnow.com',
        'mobile': '9876543210',
        'profile_photo': 'user_1_1793685393.jpg',
        'profile_photo_url': 'https://callnow.increditsolutions.in/uploads/profile_photos/user_1_1793685393.jpg',
      };
      await ConfigService.saveAuthData('mock_token', userPayload);

      await tester.pumpWidget(
        const MaterialApp(
          home: ProfileScreen(),
        ),
      );

      await tester.pumpAndSettle();

      // Locate inner CircleAvatar
      final avatars = tester.widgetList<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatars.isNotEmpty, isTrue);

      // Find avatar configured with NetworkImage
      final avatarWithNetworkImage = avatars.firstWhere(
        (a) => a.backgroundImage is NetworkImage,
        orElse: () => throw Exception('No CircleAvatar with NetworkImage found'),
      );

      final netImage = avatarWithNetworkImage.backgroundImage as NetworkImage;
      expect(netImage.url, equals('https://callnow.increditsolutions.in/uploads/profile_photos/user_1_1793685393.jpg'));
    });
  });
}
