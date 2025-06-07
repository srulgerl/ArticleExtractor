import 'package:flutter/material.dart';
import 'package:text_summarizer/App.dart';

void main() {
  runApp(
    MaterialApp(
      home: ArticleExtractorApp(),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: false),
    ),
  );
}
