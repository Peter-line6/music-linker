import requests
import spotipy
from spotipy.oauth2 import SpotifyClientCredentials
from flask import Flask, render_template, request, redirect, url_for, session
from functools import wraps
from flask_sqlalchemy import SQLAlchemy
from googleapiclient.discovery import build
import traceback

# --- CONFIGURATION DE L'APPLICATION ---
app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///links.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

#######################################################
##           COLLEZ VOS CLÉS ET SECRETS ICI          ##
#######################################################
app.config['SECRET_KEY'] = 'feccaef0267a987db55aee4402075dbd'
ADMIN_PASSWORD = 'PucUc5J%'
SPOTIPY_CLIENT_ID = "4715314dfc5e423692dfcc75c0fbbf7f"
SPOTIPY_CLIENT_SECRET = "e64e459a09534eea97c67e71ea4441ee"
YOUTUBE_API_KEY = "AIzaSyDLnA_4w7dJIi8cnCKk7iCdVJF4MvntVws"
#######################################################
##                   FIN DES SECRETS                   ##
#######################################################

# --- CONNEXION AUX APIS ---
try:
    auth_manager = SpotifyClientCredentials(client_id=SPOTIPY_CLIENT_ID, client_secret=SPOTIPY_CLIENT_SECRET)
    sp = spotipy.Spotify(auth_manager=auth_manager)
    print("Connexion a Spotify reussie.")
except Exception as e:
    print(f"Erreur de connexion a Spotify : {e}")
    sp = None
try:
    youtube = build('youtube', 'v3', developerKey=YOUTUBE_API_KEY)
    print("Connexion a YouTube reussie.")
except Exception as e:
    print(f"Erreur de connexion a YouTube : {e}")
    youtube = None

# --- MODÈLE DE LA BASE DE DONNÉES ---
class LinkPage(db.Model):
    slug = db.Column(db.String(80), primary_key=True, unique=True, nullable=False)
    track_name = db.Column(db.String(200), nullable=False)
    artist_name = db.Column(db.String(200), nullable=False)
    album_cover_url = db.Column(db.String(500), nullable=True)
    item_type = db.Column(db.String(50), nullable=False, default='Track')
    spotify_url = db.Column(db.String(500), nullable=True)
    youtube_url = db.Column(db.String(500), nullable=True)
    itunes_url = db.Column(db.String(500), nullable=True)
    tidal_url = db.Column(db.String(500), nullable=True)
    deezer_url = db.Column(db.String(500), nullable=True)
    qobuz_url = db.Column(db.String(500), nullable=True)
    bandcamp_url = db.Column(db.String(500), nullable=True)
    steam_url = db.Column(db.String(500), nullable=True)
    vgmdb_url = db.Column(db.String(500), nullable=True)
    def __repr__(self):
        return f'<LinkPage {self.slug}>'

# --- DÉCORATEUR DE SÉCURITÉ ---
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'logged_in' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

# --- ROUTES DE L'APPLICATION ---
@app.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
        if request.form['password'] == ADMIN_PASSWORD:
            session['logged_in'] = True
            return redirect(url_for('page_accueil'))
        else:
            error = 'Mot de passe incorrect.'
    return render_template('login.html', error=error)

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.route('/')
@login_required
def page_accueil():
    return render_template('index.html')

@app.route('/creer', methods=['POST'])
@login_required
def creer_page_lien():
    input_url = request.form['spotify_url']
    resultats = {}
    item_type = None
    try:
        if "spotify.com" in input_url:
            if "/track/" in input_url:
                item_type = 'track'
                item_info = sp.track(input_url.split('/')[-1].split('?')[0])
                resultats['nom_chanson'] = item_info.get('name')
                resultats['nom_artiste'] = item_info.get('artists', [{}])[0].get('name')
                resultats['pochette'] = item_info.get('album', {}).get('images', [{}])[0].get('url')
            elif "/album/" in input_url:
                item_type = 'album'
                item_info = sp.album(input_url.split('/')[-1].split('?')[0])
                resultats['nom_chanson'] = item_info.get('name')
                resultats['nom_artiste'] = item_info.get('artists', [{}])[0].get('name')
                resultats['pochette'] = item_info.get('images', [{}])[0].get('url')
            elif "/artist/" in input_url:
                item_type = 'artist'
                item_info = sp.artist(input_url.split('/')[-1].split('?')[0])
                resultats['nom_artiste'] = item_info.get('name')
                resultats['nom_chanson'] = item_info.get('name')
                if item_info.get('images'):
                    resultats['pochette'] = item_info['images'][0].get('url')
            else: return "Erreur : Lien Spotify non reconnu."
            resultats['item_type'] = item_type
            resultats['lien_spotify'] = input_url
        elif "music.apple.com" in input_url:
            item_id = input_url.split('/')[-1].split('?')[0]
            itunes_response = requests.get(f"https://itunes.apple.com/lookup?id={item_id}&entity=song,album,musicArtist")
            itunes_data = itunes_response.json()
            if itunes_data.get('resultCount', 0) == 0: return "Erreur : Impossible de trouver cet élément sur Apple Music."
            item_info = itunes_data['results'][0]
            resultats['nom_artiste'] = item_info.get('artistName')
            resultats['pochette'] = item_info.get('artworkUrl100', '').replace('100x100', '600x600')
            wrapper_type = item_info.get('wrapperType', '')
            kind = item_info.get('kind', '')
            if wrapper_type == 'track' or kind == 'song':
                item_type = 'track'
                resultats['nom_chanson'] = item_info.get('trackName')
                resultats['lien_itunes'] = item_info.get('trackViewUrl')
            elif wrapper_type == 'collection':
                item_type = 'album'
                resultats['nom_chanson'] = item_info.get('collectionName')
                resultats['lien_itunes'] = item_info.get('collectionViewUrl')
            elif wrapper_type == 'artist':
                item_type = 'artist'
                resultats['nom_chanson'] = item_info.get('artistName')
                resultats['lien_itunes'] = item_info.get('artistLinkUrl')
            resultats['item_type'] = item_type
        else:
            return "Erreur : URL non supportée."

        search_query_base = f"{resultats.get('nom_artiste')} {resultats.get('nom_chanson', '')}"
        
        if 'lien_spotify' not in resultats and sp:
            spotify_search = sp.search(q=search_query_base, type=item_type, limit=1)
            if spotify_search[f'{item_type}s']['items']:
                resultats['lien_spotify'] = spotify_search[f'{item_type}s']['items'][0]['external_urls']['spotify']
        
        if 'lien_youtube' not in resultats and youtube and item_type == 'artist':
            artist_search_query = f"{resultats.get('nom_artiste')} official"
            artist_channel_request = youtube.search().list(q=artist_search_query, part='snippet', maxResults=1, type='channel')
            artist_channel_response = artist_channel_request.execute()
            if artist_channel_response.get('items'):
                resultats['lien_youtube'] = f"https://www.youtube.com/channel/{artist_channel_response['items'][0]['id']['channelId']}"
        elif 'lien_youtube' not in resultats and youtube:
            artist_topic_query = f"{resultats.get('nom_artiste')} - Topic"
            channel_request = youtube.search().list(q=artist_topic_query, part='snippet', maxResults=1, type='channel')
            channel_response = channel_request.execute()
            channel_id = None
            if channel_response.get('items'):
                channel_id = channel_response['items'][0]['id']['channelId']
            if channel_id:
                content_query = resultats.get('nom_chanson', '')
                content_type = 'video' if item_type == 'track' else 'playlist'
                content_request = youtube.search().list(q=content_query, part='snippet', maxResults=1, type=content_type, channelId=channel_id)
                content_response = content_request.execute()
                if content_response.get('items'):
                    item = content_response['items'][0]
                    if content_type == 'video':
                        resultats['lien_youtube'] = f"https://music.youtube.com/watch?v={item['id']['videoId']}"
                    else:
                        resultats['lien_youtube'] = f"https://www.youtube.com/playlist?list={item['id']['playlistId']}"

        if 'lien_itunes' not in resultats:
            entity_map = {'track': 'song', 'album': 'album', 'artist': 'musicArtist'}
            itunes_entity = entity_map.get(item_type, 'song')
            itunes_response = requests.get("https://itunes.apple.com/search", params={'term': search_query_base, 'media': 'music', 'entity': itunes_entity, 'limit': 1})
            itunes_data = itunes_response.json()
            if itunes_data.get('resultCount', 0) > 0:
                url_map = {'track': 'trackViewUrl', 'album': 'collectionViewUrl', 'artist': 'artistLinkUrl'}
                url_key = url_map.get(item_type, 'trackViewUrl')
                resultats['lien_itunes'] = itunes_data['results'][0].get(url_key)

        resultats_template = resultats.copy()
        resultats_template['item_type'] = resultats.get('item_type', 'inconnu').capitalize()
        return render_template('edition.html', resultats=resultats_template, mode='creation')

    except Exception as e:
        print(f"Une erreur interne est survenue: {e}")
        traceback.print_exc()
        return "Une erreur interne est survenue. Verifiez le terminal pour plus de details."

@app.route('/edit/<slug>')
@login_required
def page_edition(slug):
    page_a_editer = LinkPage.query.get_or_404(slug)
    resultats = {
        'item_type': page_a_editer.item_type.capitalize(),
        'nom_chanson': page_a_editer.track_name,
        'nom_artiste': page_a_editer.artist_name,
        'pochette': page_a_editer.album_cover_url,
        'lien_spotify': page_a_editer.spotify_url,
        'lien_youtube': page_a_editer.youtube_url,
        'lien_itunes': page_a_editer.itunes_url,
        'tidal_url': page_a_editer.tidal_url,
        'deezer_url': page_a_editer.deezer_url,
        'qobuz_url': page_a_editer.qobuz_url,
        'bandcamp_url': page_a_editer.bandcamp_url,
        'steam_url': page_a_editer.steam_url,
        'vgmdb_url': page_a_editer.vgmdb_url,
        'slug_existant': page_a_editer.slug
    }
    return render_template('edition.html', resultats=resultats, mode='edition')

@app.route('/sauvegarder', methods=['POST'])
@login_required
def sauvegarder_lien():
    slug_form = request.form.get('slug', '').lower().replace(" ", "-")
    if not slug_form: return "Erreur : Le champ 'slug' est obligatoire."
    if 'mode_edition' in request.form:
        slug_original = request.form['slug_original']
        page_a_mettre_a_jour = LinkPage.query.get_or_404(slug_original)
        if slug_original != slug_form:
            existant = LinkPage.query.get(slug_form)
            if existant: return "Erreur : Ce nouveau slug est deja utilise par un autre lien."
        page_a_mettre_a_jour.slug = slug_form
        page_a_mettre_a_jour.track_name = request.form.get('track_name')
        page_a_mettre_a_jour.artist_name = request.form.get('artist_name')
        page_a_mettre_a_jour.album_cover_url = request.form.get('album_cover_url')
        page_a_mettre_a_jour.item_type = request.form.get('item_type', '').lower()
        page_a_mettre_a_jour.spotify_url = request.form.get('spotify_url')
        page_a_mettre_a_jour.youtube_url = request.form.get('youtube_url')
        page_a_mettre_a_jour.itunes_url = request.form.get('itunes_url')
        page_a_mettre_a_jour.tidal_url = request.form.get('tidal_url')
        page_a_mettre_a_jour.deezer_url = request.form.get('deezer_url')
        page_a_mettre_a_jour.qobuz_url = request.form.get('qobuz_url')
        page_a_mettre_a_jour.bandcamp_url = request.form.get('bandcamp_url')
        page_a_mettre_a_jour.steam_url = request.form.get('steam_url')
        page_a_mettre_a_jour.vgmdb_url = request.form.get('vgmdb_url')
    else:
        existant = LinkPage.query.get(slug_form)
        if existant: return "Erreur : Cette URL personnalisee existe deja."
        nouvelle_page = LinkPage(
            slug=slug_form,
            track_name=request.form.get('track_name'),
            artist_name=request.form.get('artist_name'),
            album_cover_url=request.form.get('album_cover_url'),
            item_type=request.form.get('item_type', '').lower(),
            spotify_url=request.form.get('spotify_url'),
            youtube_url=request.form.get('youtube_url'),
            itunes_url=request.form.get('itunes_url'),
            tidal_url=request.form.get('tidal_url'),
            deezer_url=request.form.get('deezer_url'),
            qobuz_url=request.form.get('qobuz_url'),
            bandcamp_url=request.form.get('bandcamp_url'),
            steam_url=request.form.get('steam_url'),
            vgmdb_url=request.form.get('vgmdb_url')
        )
        db.session.add(nouvelle_page)
    db.session.commit()
    return redirect(url_for('page_publique', slug=slug_form))

@app.route('/<slug>')
def page_publique(slug):
    page_data = LinkPage.query.get_or_404(slug)
    return render_template('public_page.html', page=page_data, session=session)