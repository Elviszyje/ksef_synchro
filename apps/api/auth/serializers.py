from django.contrib.auth import authenticate
from rest_framework import serializers
from apps.accounts.models import CustomUser


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField()
    password = serializers.CharField(write_only=True)

    def validate(self, data):
        user = authenticate(username=data['username'], password=data['password'])
        if not user:
            raise serializers.ValidationError('Nieprawidłowe dane logowania.')
        if not user.is_active:
            raise serializers.ValidationError('Konto nieaktywne.')
        data['user'] = user
        return data


class UserMeSerializer(serializers.ModelSerializer):
    company_name = serializers.SerializerMethodField()
    license_plan = serializers.SerializerMethodField()
    license_valid_until = serializers.SerializerMethodField()

    class Meta:
        model = CustomUser
        fields = [
            'id', 'username', 'email', 'first_name', 'last_name',
            'role', 'company_id', 'company_name',
            'license_plan', 'license_valid_until',
        ]

    def get_company_name(self, obj):
        return obj.company.name if obj.company else None

    def get_license_plan(self, obj):
        lic = getattr(getattr(obj, 'company', None), 'license', None)
        return lic.plan if lic else None

    def get_license_valid_until(self, obj):
        lic = getattr(getattr(obj, 'company', None), 'license', None)
        return lic.valid_until if lic else None
