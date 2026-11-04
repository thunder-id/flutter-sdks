// Copyright 2026 The ThunderID Authors
// SPDX-License-Identifier: Apache-2.0

/// Keys of the curated "anonymous animal" badge icon set (lowercase), matching the
/// `avatar:...,variant=anonymous_animal,content=<key>` logo spec scheme supported by the web
/// SDK's logo picker.
const List<String> kAnonymousAnimalNames = <String>[
  'jackalope',
  'mink',
  'otter',
  'platypus',
  'quagga',
  'raccoon',
  'skunk',
  'chameleon',
  'dingo',
  'hedgehog',
  'dinosaur',
  'capybara',
  'chinchilla',
  'chipmunk',
  'chupacabra',
  'frog',
  'giraffe',
  'hippo',
  'jackal',
];

/// Resolves an `avatar:...,variant=anonymous_animal,content=<name>` spec's animal key to its
/// bundled asset path, or `null` when [name] isn't one of [kAnonymousAnimalNames] (case-sensitive
/// lowercase match — the wire `content` value is always lowercase already).
String? anonymousAnimalAssetPath(String name) =>
    kAnonymousAnimalNames.contains(name)
        ? 'packages/thunderid_flutter/assets/logo-icons/anonymous/$name.png'
        : null;

/// Keys of the curated "anonymous entity" badge icon set (lowercase) — applications,
/// organizations, resource servers, and agents — matching the
/// `avatar:...,variant=anonymous_entity,content=<key>` logo spec scheme supported by the web
/// SDK's logo picker.
const List<String> kAnonymousEntityNames = <String>[
  'hexagon',
  'diamond',
  'cube',
  'pentagon',
  'triangle_stack',
  'chevron',
  'orbit_ring',
  'octagon',
  'star',
  'parallelogram',
  'plus_facet',
  'spiral',
  'townhouse',
  'tower',
  'dome',
  'gate',
  'pavilion',
  'spire',
  'bridge',
  'lighthouse',
  'windmill',
  'silo',
  'arch',
  'obelisk',
  'turbine',
  'anchor',
  'anvil',
  'compass',
  'key',
  'lock',
  'circuit_node',
  'antenna',
  'valve',
  'bot_head',
  'brain',
  'neural_net',
];

/// Resolves an `avatar:...,variant=anonymous_entity,content=<name>` spec's entity key to its
/// bundled asset path, or `null` when [name] isn't one of [kAnonymousEntityNames] (case-sensitive
/// lowercase match — the wire `content` value is always lowercase already).
String? anonymousEntityAssetPath(String name) =>
    kAnonymousEntityNames.contains(name)
        ? 'packages/thunderid_flutter/assets/logo-icons/entity/$name.png'
        : null;
