# Django Project CI/CD Setup Guide

Panduan ini akan membantu Anda menyiapkan Continuous Integration dan Continuous Deployment (CI/CD) untuk proyek Django Anda, menggunakan GitHub Actions untuk push otomatis ke PWS (Pacil Web Service).

## Daftar Isi
1. [Persiapan Proyek](#persiapan-proyek)
2. [Membuat Dockerfile](#membuat-dockerfile)
3. [Menyiapkan GitHub Actions](#menyiapkan-github-actions)
4. [Menangani Konflik](#menangani-konflik)
5. [Tips Tambahan](#tips-tambahan)
6. [Kontributor](#kontributor)

## Persiapan Proyek

Sebelum memulai, pastikan Anda memiliki:
- Proyek Django yang sudah berfungsi
- Akun GitHub
- Git sudah terinstal di komputer Anda

## Membuat Dockerfile

1. Buat file bernama `Dockerfile` di root direktori proyek Anda.
2. Salin kode berikut ke dalam `Dockerfile`:

```dockerfile
FROM python:3.10-slim-buster

WORKDIR /app

ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app \
    PORT=8000 \
    WEB_CONCURRENCY=2

# Install system packages required by Django.
RUN apt-get update --yes --quiet && apt-get install --yes --quiet --no-install-recommends \
&& rm -rf /var/lib/apt/lists/*

RUN addgroup --system django \
    && adduser --system --ingroup django django

# Requirements are installed here to ensure they will be cached.
COPY ./requirements.txt /requirements.txt
COPY ./custom-wheels /wheels
RUN pip install --no-index --find-links=/wheels -r /requirements.txt

# Remove wheels
RUN rm -rf /wheels

# Copy project code
COPY . .

# Run as non-root user
RUN chown -R django:django /app
USER django

RUN echo '#!/bin/bash\n\
PROJECT_NAME=$(find . -maxdepth 2 -type f -name "wsgi.py" | cut -d "/" -f 2)\n\
if [ -z "$PROJECT_NAME" ]; then\n\
    echo "Error: Could not find Django project."\n\
    exit 1\n\
fi\n\
echo "Django project name: ${PROJECT_NAME}"\n\
export DJANGO_SETTINGS_MODULE=${PROJECT_NAME}.settings\n\
python manage.py migrate\n\
python manage.py collectstatic --noinput\n\
gunicorn ${PROJECT_NAME}.wsgi:application' > /app/run.sh && \
    chmod +x /app/run.sh

# Run application
CMD ["/app/run.sh"]
```

## Menyiapkan GitHub Actions

1. Di repositori GitHub Anda, buat direktori `.github/workflows/`.
2. Di dalam direktori tersebut, buat file `ci_cd.yml`.
3. Salin kode berikut ke dalam `ci_cd.yml`:

```yaml
name: Install Dependencies and Push to PWS
on:
  push:
    branches: [ main ]
    paths-ignore:
        - '**.md'
  pull_request:
    branches: [ main ]
    paths-ignore:
        - '**.md'
jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
      with:
        fetch-depth: 0
    - name: Set up Python
      uses: actions/setup-python@v2
      with:
        python-version: '3.10'
    - name: Install dependencies
      run: python -m pip install --upgrade pip
    - name: Create custom-wheels directory
      run: mkdir -p ./custom-wheels
    - name: Download wheels
      run: pip download -r requirements.txt -d ./custom-wheels
    - name: Set up Git
      run: |
        git config --global user.name 'github-actions[bot]'
        git config --global user.email 'github-actions[bot]@users.noreply.github.com'
    - name: Check PWS remote, pull, merge, and push
      env:
        PWS_URL: ${{ secrets.PWS_URL }}
      run: |
          git add .
          git commit -m "Add installed dependencies and custom wheels" || echo "No changes to commit"
          
          # Check if master branch exists locally
          if ! git show-ref --verify --quiet refs/heads/master; then
            echo "Creating master branch"
            git branch master
          fi
          
          # Switch to master branch
          git checkout master
          
          # Try to pull and merge
          if ! git pull $PWS_URL master --no-rebase; then
            echo "Pull failed, trying to merge"
            if ! git merge origin/main -m "Merge main into master"; then
              echo "Merge failed. Attempting to resolve conflicts automatically."
              git config merge.ours.driver true
              if ! git merge -X ours origin/main -m "Merge main into master (ours strategy)"; then
                echo "Error: Unable to automatically resolve conflicts. Manual intervention required."
                exit 1
              fi
            fi
          fi
          
          # Push to master branch and capture the output
          push_output=$(git push $PWS_URL master 2>&1)
          if [[ $? -ne 0 ]]; then
            echo "Push failed with output: $push_output"
            echo "Error: Unable to push changes. Please check the error message above and resolve any conflicts manually."
            exit 1
          fi
          echo "Push successful with output: $push_output"
    - name: Clean up
      if: always()
      run: |
        rm -rf ./custom-wheels
        echo "Cleaned up custom-wheels directory"
```

4. Pastikan untuk menambahkan secret berikut di pengaturan repositori GitHub Anda (repository setting > secrets and variables > actions > repository secrets):
   - `PWS_URL`: `https://<username>:<projectpassword>@pbp.cs.ui.ac.id/<username>/<projectname>`

## Menangani Konflik

Jika terjadi konflik saat melakukan push ke PWS:
1. Workflow akan mencoba menyelesaikan konflik secara otomatis menggunakan strategi "ours".
2. Jika gagal, workflow akan berhenti dan memberikan pesan error.
3. Anda perlu menyelesaikan konflik secara manual, kemudian menjalankan workflow kembali.

## Tips Tambahan

1. Workflow ini tidak akan berjalan untuk perubahan pada file markdown (*.md).
2. Gunakan Python 3.10 untuk kompatibilitas.
3. Pastikan `requirements.txt` Anda selalu up-to-date.
4. Periksa log GitHub Actions jika terjadi masalah dalam proses deployment.
5. Direktori `custom-wheels` akan dibuat dan dihapus secara otomatis selama proses workflow.

## Kontributor

- Isa Citra Buana
- Juan Maxwell Tanaya

Selamat mencoba, dan semoga sukses dengan proyek Django Anda!
