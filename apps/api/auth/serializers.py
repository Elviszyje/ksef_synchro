from django.contrib.auth import authenticate
from rest_framework import serializers
from apps.accounts.models import CustomUser, Company


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


class UpdateProfileSerializer(serializers.Serializer):
    first_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    last_name = serializers.CharField(max_length=150, required=False, allow_blank=True)
    email = serializers.EmailField(required=False)
    password = serializers.CharField(min_length=8, required=False, write_only=True)

    def update(self, instance, validated_data):
        for field in ('first_name', 'last_name', 'email'):
            if field in validated_data:
                setattr(instance, field, validated_data[field])
        if 'password' in validated_data:
            instance.set_password(validated_data['password'])
        instance.save()
        return instance


class CompanySerializer(serializers.ModelSerializer):
    class Meta:
        model = Company
        fields = ['nip', 'name', 'address', 'bank_account']
        read_only_fields = ['nip']
