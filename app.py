import os
import requests
import traceback
import uuid
from functools import wraps
from dotenv import load_dotenv
from flask import Flask, render_template, request, redirect, url_for, session, jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate

# Charge les variables d'environnement pour le développement local
load_dotenv()

# --- CONFIGURATION DE L'APPLICATION ---
app = Flask(__name__)

# --- CONFIGURATION DES SECRETS ---
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY')
ADMIN_PASSWORD = os.environ.get('ADMIN_PASSWORD')
INTERNAL_API_KEY = os.environ.get('INTERNAL_API_KEY')

# --- CONFIGURATION DE LA BASE DE DONNÉES ---
DATABASE_URL = os.environ.get('DATABASE_URL')
if DATABASE_URL and DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)
app.config['SQLALCHEMY_DATABASE_URI'] = DATABASE_URL or 'sqlite:///links.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# --- INITIALISATION DES EXTENSIONS ---
db = SQLAlchemy(app)
migrate = Migrate(app, db)


# --- MODÈLE DE LA BASE DE DONNÉES ---
class LinkPage(db.Model):
    slug = db.Column(db.String(80), primary_key=True, unique=True, nullable=False)
    track_name = db.Column(db.String(200), nullable=False)
    artist_name = db.Column(db.String(200), nullable=False)
    album_cover_url = db.Column(db.String(500), nullable=True)
    item_type = db.Column(db.String(50), nullable=False, default='Track')
    created_at = db.Column(db.DateTime, server_default=db.func.now())
    spotify_url = db.Column(db.String(500), nullable=True)
    youtube_url = db.Column(db.String(500), nullable=True)
    itunes_url = db.Column(db.String(500), nullable=True)
    tidal_url = db.Column(db.String(500), nullable=True)
    deezer_url = db.Column(db.String(500), nullable=True)
    qobuz_url = db.Column(db.String(500), nullable=True)
    bandcamp_url = db.Column(db.String(500), nullable=True)
    steam_url = db.Column(db.String(500), nullable=True)
    steam_description = db.Column(db.Text, nullable=True)
    vgmdb_url = db.Column(db.String(500), nullable=True)

    def __repr__(self):
        return f'<LinkPage {self.slug}>'


# --- DÉCORATEUR DE SÉCURITÉ ---
def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'logged_in' not in session:
            return redirect(url_for('login', next=request.url))
        return f(*args, **kwargs)
    return decorated_function


# --- ROUTES D'AUTHENTIFICATION ---
@app.route('/login', methods=['GET', 'POST'])
def login():
    error = None
    if request.method == 'POST':
        if ADMIN_PASSWORD and request.form['password'] == ADMIN_PASSWORD:
            session['logged_in'] = True
            next_url = request.args.get('next')
            return redirect(next_url or url_for('admin_dashboard'))
        else:
            error = 'Mot de passe incorrect.'
    return render_template('login.html', error=error)


@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))


# --- ROUTES PUBLIQUES ET D'ADMINISTRATION ---
@app.route('/')
def public_home():
    return redirect("https://nowplaying.cool", code=302)


@app.route('/admin')
@login_required
def admin_dashboard():
    page = request.args.get('page', 1, type=int)
    links = LinkPage.query.order_by(LinkPage.created_at.desc()).paginate(page=page, per_page=50)
    return render_template('index.html', links=links)


@app.route('/creer', methods=['POST'])
@login_required
def creer_page_lien():
    input_url = request.form.get('spotify_url')
    if not input_url:
        return redirect(url_for('admin_dashboard'))

    songlink_api_url = f"https://api.song.link/v1-alpha.1/links?url={input_url}"
    try:
        response = requests.get(songlink_api_url)
        response.raise_for_status()
        data = response.json()
        
        entity_id = data['entityUniqueId']
        item_type_raw = entity_id.split(':')[1] if ':' in entity_id else 'inconnu'
        page_data = data['entitiesByUniqueId'][entity_id]
        
        resultats = {
            'item_type': item_type_raw.capitalize(),
            'nom_chanson': page_data.get('title'),
            'nom_artiste': page_data.get('artistName'),
            'pochette': page_data.get('thumbnailUrl'),
        }
        
        platform_map = {
            'spotify': 'lien_spotify', 'youtube': 'lien_youtube', 'appleMusic': 'lien_itunes',
            'tidal': 'lien_tidal', 'deezer': 'lien_deezer', 'qobuz': 'lien_qobuz',
            'bandcamp': 'lien_bandcamp'
        }
        
        for platform_name, platform_data in data['linksByPlatform'].items():
            if platform_name in platform_map:
                resultats[platform_map[platform_name]] = platform_data.get('url')

        return render_template('edition.html', resultats=resultats, mode='creation')

    except Exception as e:
        print(f"Une erreur interne est survenue: {e}")
        traceback.print_exc()
        return "Erreur : Impossible de trouver des liens pour cette URL. Verifiez le lien ou reessayez."


@app.route('/edit/<slug>')
@login_required
def page_edition(slug):
    page_a_editer = LinkPage.query.get_or_404(slug)
    resultats = {
        'item_type': page_a_editer.item_type, 'nom_chanson': page_a_editer.track_name,
        'nom_artiste': page_a_editer.artist_name, 'pochette': page_a_editer.album_cover_url,
        'lien_spotify': page_a_editer.spotify_url, 'lien_youtube': page_a_editer.youtube_url,
        'lien_itunes': page_a_editer.itunes_url, 'tidal_url': page_a_editer.tidal_url,
        'deezer_url': page_a_editer.deezer_url, 'qobuz_url': page_a_editer.qobuz_url,
        'bandcamp_url': page_a_editer.bandcamp_url, 'steam_url': page_a_editer.steam_url,
        'vgmdb_url': page_a_editer.vgmdb_url, 'steam_description': page_a_editer.steam_description,
        'slug_existant': page_a_editer.slug
    }
    return render_template('edition.html', resultats=resultats, mode='edition')


@app.route('/sauvegarder', methods=['POST'])
@login_required
def sauvegarder_lien():
    slug_form = request.form.get('slug', '').lower().replace(" ", "-")
    if not slug_form:
        return "Erreur : Le champ 'slug' est obligatoire."

    if 'mode_edition' in request.form:
        slug_original = request.form['slug_original']
        page = LinkPage.query.get_or_404(slug_original)
        if slug_original != slug_form and LinkPage.query.get(slug_form):
            return "Erreur : Ce nouveau slug est deja utilise par un autre lien."
    else:
        if LinkPage.query.get(slug_form):
            return "Erreur : Cette URL personnalisee existe deja."
        page = LinkPage()
        db.session.add(page)

    page.slug = slug_form
    page.track_name = request.form.get('track_name')
    page.artist_name = request.form.get('artist_name')
    page.album_cover_url = request.form.get('album_cover_url')
    page.item_type = request.form.get('item_type', '').capitalize()
    page.spotify_url = request.form.get('spotify_url')
    page.youtube_url = request.form.get('youtube_url')
    page.itunes_url = request.form.get('itunes_url')
    page.tidal_url = request.form.get('tidal_url')
    page.deezer_url = request.form.get('deezer_url')
    page.qobuz_url = request.form.get('qobuz_url')
    page.bandcamp_url = request.form.get('bandcamp_url')
    page.steam_url = request.form.get('steam_url')
    page.vgmdb_url = request.form.get('vgmdb_url')
    page.steam_description = request.form.get('steam_description')
    
    db.session.commit()
    return redirect(url_for('page_publique', slug=slug_form))


@app.route('/delete/<slug>', methods=['POST'])
@login_required
def delete_link(slug):
    link_to_delete = LinkPage.query.get_or_404(slug)
    db.session.delete(link_to_delete)
    db.session.commit()
    return redirect(url_for('admin_dashboard'))


@app.route('/<slug>')
def page_publique(slug):
    page_data = LinkPage.query.get_or_404(slug)
    plain_title = f"{page_data.track_name}, par {page_data.artist_name} - NOWPLAYING"
    
    if '(' in page_data.track_name and ')' in page_data.track_name:
        parts = page_data.track_name.split('(', 1)
        main_title = parts[0].strip()
        subtitle_part = '(' + parts[1]
        page_data.track_name = f"{main_title} <span class='subtitle'>{subtitle_part}</span>"
        
    return render_template('public_page.html', page=page_data, session=session, plain_title=plain_title)


# --- ROUTE API POUR LE RACCOURCI IOS ---
@app.route('/api/create-from-url')
def api_create_from_url():
    provided_key = request.args.get('apikey')
    if not INTERNAL_API_KEY or provided_key != INTERNAL_API_KEY:
        return jsonify({"error": "Clé d'API invalide ou manquante"}), 401

    input_url = request.args.get('url')
    if not input_url:
        return jsonify({"error": "URL manquante"}), 400

    songlink_api_url = f"https://api.song.link/v1-alpha.1/links?url={input_url}"
    try:
        response = requests.get(songlink_api_url)
        response.raise_for_status()
        data = response.json()
        
        entity_id = data['entityUniqueId']
        item_type_raw = entity_id.split(':')[1] if ':' in entity_id else 'inconnu'
        page_data = data['entitiesByUniqueId'][entity_id]
        
        new_slug = str(uuid.uuid4())[:8]
        
        nouvelle_page = LinkPage(
            slug=new_slug,
            track_name=page_data.get('title', 'Titre inconnu'),
            artist_name=page_data.get('artistName', 'Artiste inconnu'),
            album_cover_url=page_data.get('thumbnailUrl'),
            item_type=item_type_raw.capitalize(),
        )
        
        platform_map = {
            'spotify': 'spotify_url', 'youtube': 'youtube_url', 'appleMusic': 'itunes_url',
            'tidal': 'tidal_url', 'deezer': 'deezer_url', 'qobuz': 'qobuz_url',
            'bandcamp': 'bandcamp_url'
        }
        for platform_name, platform_data in data['linksByPlatform'].items():
            if platform_name in platform_map:
                db_field = platform_map[platform_name]
                setattr(nouvelle_page, db_field, platform_data.get('url'))
        
        db.session.add(nouvelle_page)
        db.session.commit()

        edit_url = url_for('page_edition', slug=new_slug, _external=True)
        return redirect(edit_url)
    except Exception as e:
        print(f"Erreur API: {e}")
        traceback.print_exc()
        return jsonify({"error": "Impossible de traiter le lien"}), 500


# --- COMMANDES CLI (pour la gestion locale/déploiement) ---
@app.cli.command("init-db")
def init_db_command():
    """Cree les tables de la base de donnees."""
    with app.app_context():
        db.create_all()
    print("Base de donnees initialisee.")

