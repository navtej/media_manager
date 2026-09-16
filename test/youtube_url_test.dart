import 'package:flutter_test/flutter_test.dart';
import 'package:movie_manager/logic/youtube_url.dart';

void main() {
  test('youtubeUrlFromTitle reads the trailing bracketed video id', () {
    expect(
      youtubeUrlFromTitle('An example video [dQw4w9WgXcQ]'),
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
    );
    expect(
      youtubeUrlFromTitle('Title [with] metadata [abc_123-xyz]'),
      'https://www.youtube.com/watch?v=abc_123-xyz',
    );
  });

  test('youtubeUrlsFromTitles skips titles without a trailing video id', () {
    expect(
      youtubeUrlsFromTitles([
        'First [first_video]',
        'No video id here',
        'Second [second-video]',
      ]),
      [
        'https://www.youtube.com/watch?v=first_video',
        'https://www.youtube.com/watch?v=second-video',
      ],
    );
  });
}
