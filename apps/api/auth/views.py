from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework_simplejwt.tokens import RefreshToken
from core.permissions import has_min_role
from .serializers import LoginSerializer, UserMeSerializer, UpdateProfileSerializer, CompanySerializer


class LoginView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data['user']
        refresh = RefreshToken.for_user(user)
        return Response({
            'access': str(refresh.access_token),
            'refresh': str(refresh),
            'user': UserMeSerializer(user).data,
        })


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            token = RefreshToken(request.data.get('refresh', ''))
            token.blacklist()
        except Exception:
            pass
        return Response({'detail': 'Wylogowano.'})


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(UserMeSerializer(request.user).data)

    def patch(self, request):
        serializer = UpdateProfileSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.update(request.user, serializer.validated_data)
        return Response(UserMeSerializer(request.user).data)


class CompanyView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        company = request.user.company
        if not company:
            return Response({'detail': 'Brak przypisanej firmy.'}, status=404)
        return Response(CompanySerializer(company).data)

    def patch(self, request):
        if not has_min_role(request.user, 'admin'):
            return Response({'detail': 'Brak uprawnień.'}, status=403)
        company = request.user.company
        if not company:
            return Response({'detail': 'Brak przypisanej firmy.'}, status=404)
        serializer = CompanySerializer(company, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)
