import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/services/themealdb_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('searchByName maps a successful meal response to recipes', () async {
    final client = MockClient(
      (_) async => http.Response('''
        {
          "meals": [
            {
              "idMeal": "52772",
              "strMeal": "Teriyaki Chicken",
              "strCategory": "Chicken",
              "strMealThumb": "https://example.com/chicken.jpg",
              "strInstructions": "Prep ingredients\\nCook everything",
              "strIngredient1": "Chicken",
              "strMeasure1": "200g",
              "strIngredient2": "Soy sauce",
              "strMeasure2": "2 tbsp",
              "strTags": "Japanese,Dinner"
            }
          ]
        }
        ''', 200),
    );

    final recipes = await TheMealDbService(
      client: client,
    ).searchByName('chicken');

    expect(recipes, hasLength(1));
    expect(recipes.single.id, 'mealdb_52772');
    expect(recipes.single.name, 'Teriyaki Chicken');
    expect(recipes.single.ingredients.map((i) => i.name), [
      'Chicken',
      'Soy sauce',
    ]);
    expect(recipes.single.steps, ['Prep ingredients', 'Cook everything']);
    expect(recipes.single.tags, ['Japanese', 'Dinner']);
  });

  test('searchByName returns empty on HTTP error', () async {
    final recipes = await TheMealDbService(
      client: MockClient((_) async => http.Response('server error', 500)),
    ).searchByName('chicken');

    expect(recipes, isEmpty);
  });

  test('searchByName returns empty on null meals', () async {
    final recipes = await TheMealDbService(
      client: MockClient((_) async => http.Response('{"meals": null}', 200)),
    ).searchByName('unknown');

    expect(recipes, isEmpty);
  });

  test('searchByName returns empty on malformed JSON', () async {
    final recipes = await TheMealDbService(
      client: MockClient((_) async => http.Response('not-json', 200)),
    ).searchByName('bad');

    expect(recipes, isEmpty);
  });

  test('searchByName returns empty on timeout', () async {
    final recipes = await TheMealDbService(
      client: MockClient((_) async => throw TimeoutException('slow')),
    ).searchByName('slow');

    expect(recipes, isEmpty);
  });

  test('searchByName decodes UTF-8 non-ASCII meal names correctly', () async {
    // Simulate a server that sends raw UTF-8 bytes (no charset in header).
    final body = '{"meals":[{"idMeal":"1","strMeal":"照り焼きチキン",'
        '"strCategory":"Chicken","strMealThumb":null,'
        '"strInstructions":"Cook"}]}';
    final bodyBytes = utf8.encode(body);

    final client = MockClient(
      (_) async => http.Response.bytes(bodyBytes, 200),
    );

    final recipes = await TheMealDbService(client: client).searchByName('test');

    expect(recipes, hasLength(1));
    expect(recipes.single.name, '照り焼きチキン');
  });
}
