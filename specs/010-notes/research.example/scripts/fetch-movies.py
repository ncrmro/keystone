#!/usr/bin/env python3
import json
import sys

# Mock data for example purposes
# In a real script, you might use `requests` to fetch from an API
movies = [
    {"title": "Dune: Part Two", "rating": 8.9, "genre": "Sci-Fi"},
    {"title": "Civil War", "rating": 7.6, "genre": "Thriller"},
    {"title": "The Fall Guy", "rating": 7.3, "genre": "Action"},
]

# Format for the agent
print("Here are the movies playing now:")
for movie in movies:
    print(f"- {movie['title']} (Rating: {movie['rating']}, Genre: {movie['genre']})")

print("\nTask: Pick one movie from this list that is a Sci-Fi thriller and explain why I should watch it.")

