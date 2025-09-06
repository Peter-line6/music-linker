import spotipy
from spotipy.oauth2 import SpotifyClientCredentials

# --- CONFIGURATION ---
# REMPLACEZ CECI PAR VOS PROPRES CLÉS
# Mettez vos identifiants entre les guillemets
CLIENT_ID = "4715314dfc5e423692dfcc75c0fbbf7f"
CLIENT_SECRET = "e64e459a09534eea97c67e71ea4441ee"
# --------------------

# On vérifie que les clés ont bien été entrées
if CLIENT_ID == "VOTRE_CLIENT_ID_ICI" or CLIENT_SECRET == "VOTRE_CLIENT_SECRET_ICI":
    print("ERREUR : Veuillez renseigner votre Client ID et Client Secret.")
else:
    # Mise en place de l'authentification
    auth_manager = SpotifyClientCredentials(client_id=CLIENT_ID, client_secret=CLIENT_SECRET)
    sp = spotipy.Spotify(auth_manager=auth_manager)

    # L'URI d'une chanson à tester (ici, "Get Lucky" de Daft Punk)
    # Vous pouvez trouver l'URI d'une chanson sur Spotify Desktop via Partager > Copier l'URI Spotify
    track_uri = 'spotify:track:2wk6xwOVfNQXjwPtE6YYUw'

    try:
        # On demande à l'API les informations sur cette chanson
        track_info = sp.track(track_uri)

        # On extrait les informations qui nous intéressent du résultat
        track_name = track_info['name']
        artist_name = track_info['artists'][0]['name']
        album_name = track_info['album']['name']
        album_cover_url = track_info['album']['images'][0]['url']

        # On affiche le résultat
        print("--- Informations récupérées ---")
        print(f"Titre   : {track_name}")
        print(f"Artiste : {artist_name}")
        print(f"Album   : {album_name}")
        print(f"Pochette: {album_cover_url}")
        print("-------------------------------")

    except Exception as e:
        print(f"Une erreur est survenue : {e}")