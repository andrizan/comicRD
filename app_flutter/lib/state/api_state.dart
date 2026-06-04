import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/comicrd_api.dart';

final comicRdApiProvider = Provider<ComicRdApi>((ref) => const ComicRdApi());
