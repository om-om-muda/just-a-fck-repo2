from django.db import models

# Create your models here.
class MoodEntry(models.Model):
    mood = models.CharField(max_length=255)
    time = models.DateField(auto_now_add=True)
    feelings = models.TextField()
    mood_intensity = models.IntegerField()
    sadness_level  = models.IntegerField()

    @property
    def is_happy(self):
        return self.mood_intensity > 5 and self.sadness_level < 5