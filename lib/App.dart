// ignore_for_file: library_private_types_in_public_api

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';

class ArticleExtractorWithRetry {
  static const String baseUrl =
      'https://article-extractor-and-summarizer.p.rapidapi.com';
  static const String apiKey =
      '4e34b37fe2mshd5d8f4c67dfb593p1ce02fjsne0ac2b8c4726';

  // Retry логик нэмсэн функц
  static Future<Map<String, dynamic>> extractWithRetry({
    required String url,
    int maxRetries = 3,
    Duration delay = const Duration(seconds: 2),
  }) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await http
            .get(
              Uri.parse('$baseUrl/summarize').replace(
                queryParameters: {'url': url, 'lang': 'en', 'length': '3'},
              ),
              headers: {
                'X-RapidAPI-Key': apiKey,
                'X-RapidAPI-Host':
                    'article-extractor-and-summarizer.p.rapidapi.com',
                'User-Agent': 'Flutter-App/1.0',
                'Accept': 'application/json',
              },
            )
            .timeout(
              Duration(seconds: 30),
              onTimeout: () {
                throw SocketException('Request timeout');
              },
            );

        print('Status Code: ${response.statusCode}');
        print('Response Headers: ${response.headers}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          return {'success': true, 'data': data, 'attempt': attempt};
        } else if (response.statusCode == 503) {
          print('503 алдаа: Сервер түр зуур ажиллахгүй байна');
          if (attempt < maxRetries) {
            print('${delay.inSeconds} секунд хүлээж байна...');
            await Future.delayed(delay);
            // Дараагийн оролдлогод илүү удаан хүлээх
            delay = Duration(seconds: delay.inSeconds * 2);
            continue;
          }
        } else if (response.statusCode == 429) {
          print('429 алдаа: Хэт олон request илгээсэн');
          if (attempt < maxRetries) {
            await Future.delayed(Duration(seconds: 60)); // 1 минут хүлээх
            continue;
          }
        } else {
          return {
            'success': false,
            'error': 'HTTP ${response.statusCode}: ${response.body}',
            'attempt': attempt,
          };
        }
      } catch (e) {
        print('Алдаа (оролдлого $attempt): $e');
        if (attempt < maxRetries) {
          print('${delay.inSeconds} секунд хүлээж байна...');
          await Future.delayed(delay);
          delay = Duration(seconds: delay.inSeconds * 2);
          continue;
        }
      }
    }

    return {
      'success': false,
      'error': '503 Service Unavailable - $maxRetries оролдлого бүгд амжилтгүй',
      'attempt': maxRetries,
    };
  }

  // Өөр endpoint ашиглах
  static Future<Map<String, dynamic>> tryAlternativeEndpoint(String url) async {
    try {
      // Extract only endpoint (without summarize)
      final response = await http
          .get(
            Uri.parse(
              '$baseUrl/extract',
            ).replace(queryParameters: {'url': url}),
            headers: {
              'X-RapidAPI-Key': apiKey,
              'X-RapidAPI-Host':
                  'article-extractor-and-summarizer.p.rapidapi.com',
            },
          )
          .timeout(Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {'success': true, 'data': data, 'endpoint': 'extract'};
      }
    } catch (e) {
      print('Alternative endpoint алдаа: $e');
    }

    return {
      'success': false,
      'error': 'Alternative endpoint ч ажиллахгүй байна',
    };
  }

  // Сервер статус шалгах
  static Future<Map<String, dynamic>> checkServerStatus() async {
    try {
      final response = await http
          .head(
            Uri.parse(baseUrl),
            headers: {
              'X-RapidAPI-Key': apiKey,
              'X-RapidAPI-Host':
                  'article-extractor-and-summarizer.p.rapidapi.com',
            },
          )
          .timeout(Duration(seconds: 10));

      return {
        'available': response.statusCode != 503,
        'statusCode': response.statusCode,
        'message': response.statusCode == 503
            ? 'Сервер түр зуур ажиллахгүй байна'
            : 'Сервер ажиллаж байна',
      };
    } catch (e) {
      return {
        'available': false,
        'statusCode': 0,
        'message': 'Серверт холбогдож чадахгүй байна: $e',
      };
    }
  }
}

// UI Widget with error handling
class ArticleExtractorApp extends StatefulWidget {
  const ArticleExtractorApp({super.key});

  @override
  _ArticleExtractorAppState createState() => _ArticleExtractorAppState();
}

class _ArticleExtractorAppState extends State<ArticleExtractorApp> {
  final TextEditingController _urlController = TextEditingController(
    text: 'https://www.bbc.com/news',
  );

  Map<String, dynamic>? _result;
  bool _isLoading = false;
  String? _errorMessage;
  String _statusMessage = '';

  Future<void> _extractArticle() async {
    if (_urlController.text.isEmpty) {
      setState(() {
        _errorMessage = 'URL оруулна уу';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
      _statusMessage = 'Эхлүүлж байна...';
    });

    // Эхлээд сервер статус шалгах
    setState(() {
      _statusMessage = 'Сервер статус шалгаж байна...';
    });

    final serverStatus = await ArticleExtractorWithRetry.checkServerStatus();

    if (!serverStatus['available']) {
      setState(() {
        _errorMessage = serverStatus['message'];
        _isLoading = false;
        _statusMessage = '';
      });
      return;
    }

    // Retry-тэй extract хийх
    setState(() {
      _statusMessage = 'Article татаж байна...';
    });

    final result = await ArticleExtractorWithRetry.extractWithRetry(
      url: _urlController.text,
      maxRetries: 3,
    );

    if (!result['success']) {
      // Alternative endpoint оролдох
      setState(() {
        _statusMessage = 'Өөр арга оролдож байна...';
      });

      final altResult = await ArticleExtractorWithRetry.tryAlternativeEndpoint(
        _urlController.text,
      );

      if (altResult['success']) {
        setState(() {
          _result = altResult['data'];
          _isLoading = false;
          _statusMessage = '';
        });
        return;
      }
    }

    setState(() {
      if (result['success']) {
        _result = result['data'];
      } else {
        _errorMessage = result['error'];
      }
      _isLoading = false;
      _statusMessage = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Article Extractor'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'Article URL',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
            ),
            SizedBox(height: 16),

            ElevatedButton(
              onPressed: _isLoading ? null : _extractArticle,
              child: _isLoading
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        if (_statusMessage.isNotEmpty) ...[
                          SizedBox(height: 8),
                          Text(_statusMessage, style: TextStyle(fontSize: 12)),
                        ],
                      ],
                    )
                  : Text('Article татах'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.deepPurple,
              ),
            ),

            SizedBox(height: 20),

            // Алдааны мэдээлэл
            if (_errorMessage != null)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          'Алдаа гарлаа:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(_errorMessage!),
                    SizedBox(height: 12),
                    Text(
                      '💡 Зөвлөмжүүд:\n'
                      '• Хэдэн минутын дараа дахин оролдоно уу\n'
                      '• Интернет холболтоо шалгана уу\n'
                      '• API key зөв эсэхийг шалгана уу\n'
                      '• Өөр URL оролдоно уу',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),

            // Амжилттай үр дүн
            if (_result != null)
              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green),
                            SizedBox(width: 8),
                            Text(
                              'Амжилттай!',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        if (_result!['title'] != null) ...[
                          Text(
                            'Гарчиг:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(_result!['title']),
                          SizedBox(height: 12),
                        ],
                        if (_result!['summary'] != null) ...[
                          Text(
                            'Товчлол:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(_result!['summary']),
                          SizedBox(height: 12),
                        ],
                        if (_result!['content'] != null) ...[
                          Text(
                            'Агуулга:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _result!['content'].toString().substring(
                              0,
                              _result!['content'].toString().length > 500
                                  ? 500
                                  : _result!['content'].toString().length,
                            ),
                          ),
                          if (_result!['content'].toString().length > 500)
                            Text(
                              '...',
                              style: TextStyle(fontStyle: FontStyle.italic),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}
