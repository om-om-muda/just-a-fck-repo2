# Django Project CI/CD Setup Guide

Panduan ini akan membantu Anda menyiapkan Continuous Integration dan Continuous Deployment (CI/CD) untuk proyek Django Anda, mulai dari pembuatan Dockerfile hingga konfigurasi GitHub Actions.

## Daftar Isi
1. [Persiapan Proyek](#persiapan-proyek)
2. [Membuat Dockerfile](#membuat-dockerfile)
3. [Menyiapkan GitHub Actions](#menyiapkan-github-actions)
4. [Menangani Konflik](#menangani-konflik)
5. [Tips Tambahan](#tips-tambahan)
7. [Kontributor](#kontributor)

## Persiapan Proyek

Sebelum memulai, pastikan Anda memiliki:
- Proyek Django yang sudah berfungsi
- Akun GitHub
- Git sudah terinstal di komputer Anda

## Membuat Dockerfile

1. Buat file bernama `Dockerfile` di root direktori proyek Anda.
2. Salin kode berikut ke dalam `Dockerfile`:

```dockerfile
FROM python:3.9

WORKDIR /app

# Copy pre-downloaded wheels
COPY ./custom-wheels /wheels

# Copy the requirements file
COPY requirements.txt .

# Install dependencies from wheels
RUN pip install --no-index --find-links=/wheels -r requirements.txt

# Copy the rest of the application
COPY . .

# Create the run script with project name detection
RUN echo '#!/bin/bash\n\
PROJECT_NAME=$(find . -maxdepth 2 -type f -name "wsgi.py" | cut -d "/" -f 2)\n\
if [ -z "$PROJECT_NAME" ]; then\n\
    echo "Error: Could not find Django project."\n\
    exit 1\n\
fi\n\
echo "Django project name: ${PROJECT_NAME}"\n\
python manage.py migrate\n\
python manage.py collectstatic --noinput\n\
gunicorn ${PROJECT_NAME}.wsgi:application' > /app/run.sh && \
    chmod +x /app/run.sh

# Run the application
CMD ["/app/run.sh"]
```

Dockerfile ini akan:
- Menggunakan Python 3.9 sebagai base image
- Menginstall dependensi dari wheels yang telah di-download sebelumnya
- Mencari nama proyek Django secara otomatis
- Menjalankan migrasi dan mengumpulkan file statis
- Menjalankan aplikasi menggunakan Gunicorn

## Menyiapkan GitHub Actions

1. Di repositori lokal Anda, buat direktori `.github/workflows/`.
2. Di dalam direktori tersebut, buat file `ci_cd.yml`.
3. Salin kode berikut ke dalam `ci_cd.yml`:

```yaml
name: Install Dependencies and Handle Conflicts

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build-and-push:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v3
      with:
        fetch-depth: 0

    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.9'

    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install PyGithub

    - name: Create custom-wheels directory and download wheels
      run: |
        mkdir -p ./custom-wheels
        pip download -r requirements.txt -d ./custom-wheels

    - name: Set up Git
      run: |
        git config --global user.name "${{ secrets.GH_USERNAME }}"
        git config --global user.email "${{secrets.GH_EMAIL}}"

    - name: Check PWS remote, pull, and handle conflicts
      env:
        GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      run: |
        # Set up credential helper
        git config --global credential.helper store
        echo "https://${{ secrets.PWS_USERNAME }}:${{ secrets.PWS_PASSWORD }}@pbp.cs.ui.ac.id" > ~/.git-credentials
        PWS_URL="${{secrets.PWS_URL}}"
        if git remote | grep -q "^pws$"; then
          echo "PWS remote exists. Updating URL."
          git remote set-url pws "$PWS_URL"
        else
          echo "PWS remote does not exist. Adding it."
          git remote add pws "$PWS_URL"
        fi
        
        git add .
        git commit -m "Add installed dependencies and custom wheels" || echo "No changes to commit"
        
        # Check if master branch exists locally
        if ! git show-ref --verify --quiet refs/heads/master; then
          echo "Creating master branch"
          git branch master
        fi
        
        # Switch to master branch
        git checkout master
        
        # Try to pull
        if ! git pull pws master --no-rebase; then
          echo "Pull failed, conflicts detected."
          
          # Create a new branch for conflicts
          conflict_branch="resolve-conflicts-$(date +%Y%m%d-%H%M%S)"
          git checkout -b $conflict_branch
          
          # Stage all files, including those with conflicts
          git add .
          
          # Commit the conflicting state
          git commit -m "Conflicting state for manual resolution"
          
          # Push the conflict branch to GitHub
          git push origin $conflict_branch
          
          # Create a Pull Request using PyGithub
          echo "import os" > create_pr.py
          echo "from github import Github" >> create_pr.py
          echo "g = Github(os.environ['GITHUB_TOKEN'])" >> create_pr.py
          echo "repo = g.get_repo(os.environ['GITHUB_REPOSITORY'])" >> create_pr.py
          echo "pr = repo.create_pull(" >> create_pr.py
          echo "    title='Resolve conflicts with PWS'," >> create_pr.py
          echo "    body='Conflicts were detected when trying to merge with PWS. Please resolve these conflicts manually.'," >> create_pr.py
          echo "    head=f'{conflict_branch}'," >> create_pr.py
          echo "    base='master'" >> create_pr.py
          echo ")" >> create_pr.py
          echo "print(f'Pull Request created: {pr.html_url}')" >> create_pr.py
          python create_pr.py
          
          echo "Conflicts detected. A new branch '$conflict_branch' has been created and a Pull Request has been opened for manual resolution."
          exit 1
        fi
        
        # If we got here, pull was successful
        echo "Pull successful, pushing changes"
        if ! git push pws master; then
          echo "Push failed. Please check the error message above and resolve any issues manually."
          exit 1
        fi
        echo "Push successful"

    - name: Clean up
      if: always()
      run: |
        rm -f ~/.git-credentials
        rm -rf ./custom-wheels
        echo "Cleaned up credentials and custom-wheels directory"
```

4. Pastikan untuk menambahkan secrets berikut di pengaturan repositori GitHub Anda:
Di halaman repository anda, tekan settings lalu tekan secrets and variables kemudian tekan actions lalu tambahkan repository secret.
   - `GH_USERNAME`: Username GitHub Anda
   - `GH_EMAIL`: Email GitHub Anda
   - `PWS_USERNAME`: Username untuk PWS
   - `PWS_PASSWORD`: Password untuk PWS
   - `PWS_URL`: URL repositori project PWS (contoh: http://pbp.cs.ui.ac.id/isa.citra/xxx)
5. Push

## Menangani Konflik

Jika terjadi konflik saat melakukan push ke PWS:
1. GitHub Actions akan membuat branch baru dengan nama `resolve-conflicts-[timestamp]`.
2. Sebuah Pull Request akan dibuat secara otomatis.
3. Buka Pull Request tersebut dan selesaikan konflik secara manual melalui interface GitHub.
4. Setelah konflik diselesaikan dan Pull Request di-merge, jalankan workflow GitHub Actions lagi.

## Tips Tambahan

1. Selalu pull perubahan terbaru dari repositori PWS sebelum memulai pengembangan lokal.
2. Gunakan branch terpisah untuk fitur-fitur baru untuk menghindari konflik dengan `master`.
3. Lakukan commit dan push secara teratur untuk meminimalkan konflik besar.
4. Jika Anda mengalami masalah, jangan ragu untuk meminta bantuan dari dosen atau asisten.

## Kontributor

- Isa Citra Buana

Selamat mencoba, dan semoga sukses dengan proyek Django Anda!