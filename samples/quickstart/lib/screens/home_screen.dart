/*
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:thunderid_flutter/thunderid_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      Future.microtask(_logToken);
    }
  }

  Future<void> _logToken() async {
    final thunder = ThunderIDProvider.of(context);
    try {
      final token = await thunder.client.getAccessToken();
      debugPrint('[HomeScreen] access token: $token');
      debugPrint('[HomeScreen] token payload: ${_decodeJwtPayload(token)}');
    } catch (e) {
      debugPrint('[HomeScreen] could not get access token: $e');
    }
  }

  String _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return '(not a JWT)';
      final padded = parts[1].padRight((parts[1].length + 3) ~/ 4 * 4, '=');
      return utf8.decode(base64Url.decode(padded));
    } catch (e) {
      return '(decode error: $e)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _navIndex,
        children: [
          _ExploreTab(onProfileTap: () => setState(() => _navIndex = 4)),
          const _PlaceholderTab(label: 'Saved', icon: Icons.favorite_outline),
          const _PlaceholderTab(label: 'Trips', icon: Icons.card_travel_outlined),
          const _PlaceholderTab(label: 'Inbox', icon: Icons.chat_bubble_outline),
          const _ProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.favorite_outline),
            selectedIcon: Icon(Icons.favorite),
            label: 'Saved',
          ),
          NavigationDestination(
            icon: Icon(Icons.card_travel_outlined),
            selectedIcon: Icon(Icons.card_travel),
            label: 'Trips',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Inbox',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Explore tab
// ─────────────────────────────────────────────────────────────────────────────

class _ExploreTab extends StatefulWidget {
  final VoidCallback onProfileTap;
  const _ExploreTab({required this.onProfileTap});

  @override
  State<_ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<_ExploreTab> {
  int _categoryIndex = 0;
  int _sortIndex = 0;

  static const _categories = ['Stays', 'Experiences', 'Adventures', 'Luxe'];
  static const _sorts = ['Popular', 'Near', 'Best Price'];
  static const _categoryIcons = [
    Icons.home_outlined,
    Icons.tour_outlined,
    Icons.terrain,
    Icons.diamond_outlined,
  ];

  static const _listings = [
    _Listing(
      title: 'Cozy Mountain Retreat',
      location: 'Aspen, Colorado',
      price: 189,
      rating: 4.92,
      imageUrl: 'https://picsum.photos/seed/acme1/400/280',
    ),
    _Listing(
      title: 'Beachfront Villa',
      location: 'Malibu, California',
      price: 342,
      rating: 4.87,
      imageUrl: 'https://picsum.photos/seed/acme2/400/280',
    ),
    _Listing(
      title: 'City Centre Loft',
      location: 'New York, NY',
      price: 215,
      rating: 4.78,
      imageUrl: 'https://picsum.photos/seed/acme3/400/280',
    ),
    _Listing(
      title: 'Lakeside Cabin',
      location: 'Lake Tahoe, Nevada',
      price: 156,
      rating: 4.95,
      imageUrl: 'https://picsum.photos/seed/acme4/400/280',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final thunder = ThunderIDProvider.of(context);
    final user = thunder.user;
    final firstName = (user?.claims?['given_name'] as String?)?.isNotEmpty == true
        ? user!.claims!['given_name'] as String
        : user?.displayName?.split(' ').first ?? 'there';
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          // ── Top bar ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.home_filled, color: cs.primary, size: 26),
                  const SizedBox(width: 6),
                  Text(
                    'ACME Booking',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onProfileTap,
                    child: _UserAvatar(user: user, radius: 18),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),

          // ── Welcome heading ─────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Text(
                'Where Would you\nLike to Stay, $firstName?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),

          // ── Search bar ──────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search destinations...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),

          // ── Category chips ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 0, 0),
              child: SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (ctx, i) {
                    final selected = i == _categoryIndex;
                    return GestureDetector(
                      onTap: () => setState(() => _categoryIndex = i),
                      child: Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: selected
                                  ? cs.primary
                                  : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              _categoryIcons[i],
                              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _categories[i],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: selected ? cs.primary : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // ── Sort tabs ───────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(
                children: [
                  ..._sorts.asMap().entries.map((e) {
                    final selected = e.key == _sortIndex;
                    return Padding(
                      padding: EdgeInsets.only(
                          right: e.key < _sorts.length - 1 ? 20 : 0),
                      child: GestureDetector(
                        onTap: () => setState(() => _sortIndex = e.key),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.value,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: selected
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (selected)
                              Container(
                                height: 2,
                                width: 28,
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              )
                            else
                              const SizedBox(height: 2),
                          ],
                        ),
                      ),
                    );
                  }),
                  const Spacer(),
                  Text(
                    'See More',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Listings grid ───────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            sliver: SliverGrid.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.7,
              children:
                  _listings.map((l) => _ListingCard(listing: l)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile tab
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileTab extends StatelessWidget {
  const _ProfileTab();

  @override
  Widget build(BuildContext context) {
    final thunder = ThunderIDProvider.of(context);
    final user = thunder.user;
    final cs = Theme.of(context).colorScheme;

    final givenName = user?.claims?['given_name'] as String? ?? '';
    final familyName = user?.claims?['family_name'] as String? ?? '';
    final fullName = [givenName, familyName]
        .where((s) => s.isNotEmpty)
        .join(' ')
        .trim();
    final displayName =
        fullName.isNotEmpty ? fullName : (user?.username ?? 'Guest');

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Row(
              children: [
                Text(
                  'Profile',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Profile card ──────────────────────────────────────────────
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: cs.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        _UserAvatar(user: user, radius: 40),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.verified,
                              color: cs.onPrimary,
                              size: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Los Angeles, CA',
                            style:
                                TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Stats card ────────────────────────────────────────────────
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: cs.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  children: [
                    const _StatItem(value: '24', label: 'Trips'),
                    _VerticalDivider(),
                    const _StatItem(value: '22', label: 'Reviews'),
                    _VerticalDivider(),
                    const _StatItem(value: '2', label: 'Years on ACME'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Feature cards ─────────────────────────────────────────────
            const Row(
              children: [
                Expanded(
                  child: _FeatureCard(
                    label: 'Past trips',
                    imageUrl: 'https://picsum.photos/seed/trips/300/200',
                    isNew: true,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: _FeatureCard(
                    label: 'Connections',
                    imageUrl: 'https://picsum.photos/seed/connect/300/200',
                    isNew: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Edit profile ──────────────────────────────────────────────
            OutlinedButton.icon(
              onPressed: () => _showEditProfile(context),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit Profile'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 12),

            // ── Sign out ──────────────────────────────────────────────────
            BaseSignOutButton(
              builder: (ctx, isLoading) => OutlinedButton.icon(
                onPressed: null,
                icon: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditProfile(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        expand: false,
        builder: (ctx, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: UserProfile(
            onSaved: () => Navigator.pop(ctx),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Placeholder tab
// ─────────────────────────────────────────────────────────────────────────────

class _PlaceholderTab extends StatelessWidget {
  final String label;
  final IconData icon;
  const _PlaceholderTab({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Coming soon',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _UserAvatar extends StatelessWidget {
  final dynamic user;
  final double radius;
  const _UserAvatar({this.user, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pictureUrl = (user?.profilePicture as String?)?.isNotEmpty == true
        ? user!.profilePicture as String
        : (user?.claims?['picture'] as String?)?.isNotEmpty == true
            ? user!.claims!['picture'] as String
            : null;
    if (pictureUrl != null) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(pictureUrl),
        onBackgroundImageError: (_, __) {},
        backgroundColor: cs.primaryContainer,
      );
    }
    final displayName = user?.displayName as String?;
    final email = user?.email as String?;
    final initial = displayName?.isNotEmpty == true
        ? displayName![0].toUpperCase()
        : (email?.isNotEmpty == true ? email![0].toUpperCase() : '?');
    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.9,
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      width: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final String label;
  final String imageUrl;
  final bool isNew;
  const _FeatureCard(
      {required this.label, required this.imageUrl, this.isNew = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: cs.surfaceContainerHighest),
            ),
            if (isNew)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'NEW',
                    style: TextStyle(
                      color: cs.onPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Listing data & card
// ─────────────────────────────────────────────────────────────────────────────

class _Listing {
  final String title;
  final String location;
  final int price;
  final double rating;
  final String imageUrl;

  const _Listing({
    required this.title,
    required this.location,
    required this.price,
    required this.rating,
    required this.imageUrl,
  });
}

class _ListingCard extends StatelessWidget {
  final _Listing listing;
  const _ListingCard({required this.listing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  listing.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Container(color: cs.surfaceContainerHighest),
                ),
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(Icons.favorite_outline,
                      color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        listing.location,
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.star, size: 11, color: cs.primary),
                    const SizedBox(width: 2),
                    Text(
                      listing.rating.toStringAsFixed(2),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  listing.title,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '\$${listing.price}/night',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
