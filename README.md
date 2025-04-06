# Surfer Redmine Auto Installer

This script automates the installation of Redmine (renamed as "Surfer") on an Ubuntu Server 24.04.2 LTS environment.

---

## 📦 Features

- Installs and builds Ruby 3.3.7
- Installs MySQL, Apache, Passenger, ImageMagick, Redis
- Creates MySQL user and database with:
  - **Username:** Surfer
  - **Password:** dude
- Sets up Redmine from SVN (6.0-stable branch)
- Configures Apache and Passenger
- Configures Sidekiq for background job processing
- Includes checks to safely re-run the script

---

## 🚀 Usage

### 1. Download the script

```bash
wget https://path.to/setup_surfer_redmine.sh
```

### 2. Make it executable

```bash
chmod +x setup_surfer_redmine.sh
```

### 3. Run it as root

```bash
sudo ./setup_surfer_redmine.sh
```

---

## 🖼️ Setup Screenshots (Placeholders)

### 1. Running the Script

![Terminal Output](images/setup-terminal.png)

### 2. Redmine Login Page

![Redmine Login](images/redmine-login.png)

### 3. Redmine Dashboard

![Redmine Dashboard](images/redmine-dashboard.png)

---

## 🔗 Useful Links

- [Redmine Official Docs](https://www.redmine.org/projects/redmine/wiki)
- [Passenger with Apache Docs](https://www.phusionpassenger.com/docs/)
- [Sidekiq Monitoring](https://github.com/mperham/sidekiq/wiki/Monitoring)

---

## ⚙️ Advanced Configuration

### Running Redmine in a Subdirectory

```apache
Alias /surfer /var/lib/surfer/public
<Location /surfer>
  PassengerBaseURI /surfer
  PassengerAppRoot /var/lib/surfer
</Location>
```

Then recompile assets:

```bash
RAILS_RELATIVE_URL_ROOT=/surfer sudo -u www-data bundle exec rake assets:precompile RAILS_ENV=production
```

### SSL with Let's Encrypt

Install Certbot and set up a secure Redmine instance:

```bash
sudo apt install certbot python3-certbot-apache
sudo certbot --apache
```

### Running Sidekiq as a Service

Use Supervisor or Systemd to keep Sidekiq running in production.

---

## 📜 License

MIT – Free to use and modify.
