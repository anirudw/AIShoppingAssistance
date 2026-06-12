import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:camera/camera.dart';
import '../models/cart_item_model.dart';

class ChromaDbClient {
  static const String _baseUrl = 'https://api.trychroma.com/api/v1'; // Update to the specific cloud endpoint if different
  final String _tenant = '99526d4b-48cf-4b20-896b-0947aa36d4ab';
  final String _database = 'QLESS';

  late final String _apiKey;

  ChromaDbClient() {
    _apiKey = dotenv.env['CHROMA_API_KEY'] ?? '';
    if (_apiKey.isEmpty) {
      debugPrint('Warning: CHROMA_API_KEY is not set in .env');
    }
  }

  Map<String, String> get _headers => {
        'x-chroma-token': _apiKey,
        'Content-Type': 'application/json',
      };

  // Helper method to build query parameters
  String _buildUrl(String path) {
    return '$_baseUrl/$path?tenant=$_tenant&database=$_database';
  }

  /// Example method to query a collection
  Future<Map<String, dynamic>?> queryCollection({
    required String collectionId,
    required List<List<double>> queryEmbeddings,
    int nResults = 10,
  }) async {
    final url = Uri.parse(_buildUrl('collections/$collectionId/query'));

    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'query_embeddings': queryEmbeddings,
          'n_results': nResults,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('ChromaDB query failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error querying ChromaDB: $e');
      return null;
    }
  }

  /// Temporary method to check database connectivity
  Future<String> checkConnectivity() async {
    const collectionId = 'c1102322-920e-4775-96c1-e324bdadaa1d';
    final url = Uri.parse('https://api.trychroma.com/api/v2/tenants/$_tenant/databases/$_database/collections/$collectionId/get');
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({'limit': 1}),
      );
      if (response.statusCode == 200) {
        return "Connected: OK";
      } else {
        return "Failed: ${response.statusCode} - ${response.body}";
      }
    } catch (e) {
      return "Error: $e";
    }
  }

  /// Example method to send a prompt to Chef RAG
  /// In a real scenario, this might connect to a custom backend or an LLM service
  /// integrated with ChromaDB, rather than just querying embeddings directly.
  Future<String> askChefRag(String prompt) async {
    // Placeholder for actual RAG logic
    debugPrint('Asking Chef RAG: $prompt');
    await Future.delayed(const Duration(seconds: 1)); // Simulate network call
    return "This is a simulated response for: $prompt. To unlock Neapolitan precision, add Basil and Mozzarella!";
  }

  /// Method to search an item by photo using custom Hugging Face Space directly
  Future<CartItemModel?> searchItemByPhoto(XFile photo) async {
    debugPrint('--- CHROMA SIMILARITY SEARCH START ---');
    debugPrint('Captured photo path: ${photo.path}');
    
    // The collection ID for 'supermarket_catalog'
    const collectionId = 'c1102322-920e-4775-96c1-e324bdadaa1d';
    // Use the v2 API endpoint for ChromaDB Cloud
    final url = Uri.parse('https://api.trychroma.com/api/v2/tenants/$_tenant/databases/$_database/collections/$collectionId/query');
    debugPrint('Request URL: $url');
    
    List<double> queryEmbedding;

    try {
      debugPrint('Uploading image directly to custom Hugging Face Space & generating CLIP embedding...');
      final bytes = await photo.readAsBytes();
      
      final String spaceUrl = dotenv.env['HF_SPACE_URL'] ?? '';
      if (spaceUrl.isEmpty) {
        throw Exception('HF_SPACE_URL is not configured in .env');
      }

      final request = http.MultipartRequest('POST', Uri.parse(spaceUrl));
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: 'image.jpg',
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          queryEmbedding = List<double>.from(data['embedding']);
          debugPrint('Successfully received CLIP embedding from HF Space (dimension: ${queryEmbedding.length})');
        } else {
          throw Exception('HF Space error: ${data['message']}');
        }
      } else {
        throw Exception('Failed to connect to HF Space: Status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error generating CLIP embedding: $e. Falling back to mock.');
      queryEmbedding = _generateMockEmbedding();
    }

    try {
      debugPrint('Sending POST request to ChromaDB with actual CLIP embedding...');
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode({
          'query_embeddings': [queryEmbedding],
          'n_results': 1,
        }),
      );

      debugPrint('ChromaDB Response Status Code: ${response.statusCode}');
      debugPrint('ChromaDB Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final metadatas = data['metadatas'] as List;
        final distances = data['distances'] as List;
        
        if (metadatas.isNotEmpty && metadatas[0].isNotEmpty) {
          final itemMeta = metadatas[0][0];
          final rawProductName = itemMeta['product_name'] ?? 'Unknown Item';
          // Strip trailing index numbers (e.g. -2, -3) to allow proper grouping of identical products
          final productName = rawProductName.toString().replaceAll(RegExp(r'-\d+$'), '');
          final double distance = (distances.isNotEmpty && distances[0].isNotEmpty)
              ? (distances[0][0] as num).toDouble()
              : 2.0;

          debugPrint('Matched Product Name: $productName, Distance: $distance');

          // Threshold check: L2 distance for normalized vectors ranges from 0 to 4.
          // A distance of 1.0 corresponds to a cosine similarity of 0.5.
          const double threshold = 1.0;
          if (distance > threshold) {
            debugPrint('Match rejected: Distance $distance exceeds threshold $threshold');
            debugPrint('--- CHROMA SIMILARITY SEARCH END (NO CONFIDENT MATCH) ---');
            return null;
          }
          
          debugPrint('--- CHROMA SIMILARITY SEARCH END (SUCCESS) ---');
          
          return CartItemModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            name: productName.replaceAll('-', ' ').toUpperCase(),
            details: "1 Item • \$2.99", // Mocking price since it isn't in DB
            imageUrl: "https://images.unsplash.com/photo-1542838132-92c53300491e?q=80&w=200&auto=format&fit=crop",
            price: 2.99,
            quantity: 1,
          );
        } else {
          debugPrint('Warning: Empty results or metadata returned from ChromaDB.');
        }
      } else {
        throw Exception('ChromaDB query failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Error querying ChromaDB: $e');
      debugPrint('--- CHROMA SIMILARITY SEARCH END (ERROR) ---');
      throw Exception('Failed to connect to ChromaDB: $e');
    }
    debugPrint('--- CHROMA SIMILARITY SEARCH END (NO MATCH) ---');
    return null;
  }

  List<double> _generateMockEmbedding() {
    final random = Random();
    return List.generate(512, (_) => random.nextDouble() * 2 - 1);
  }


}
