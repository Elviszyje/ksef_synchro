"""
python manage.py seed_demo
Generuje przykładowe faktury kosztowe do testów UI.
"""
import random
from datetime import date, timedelta
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.accounts.models import CustomUser
from apps.invoices.models import Invoice, InvoiceStatusLog

SELLERS = [
    ("Microsoft Polska Sp. z o.o.", "5272595893", "ul. Al. Jerozolimskie 195A, 02-222 Warszawa"),
    ("Google Poland Sp. z o.o.", "9512255049", "ul. Emilii Plater 53, 00-113 Warszawa"),
    ("OVH Sp. z o.o.", "5213494975", "ul. Swobodna 1, 50-088 Wrocław"),
    ("Adobe Systems Poland Sp. z o.o.", "5272404500", "ul. Inflancka 4B, 00-189 Warszawa"),
    ("Amazon Web Services EMEA SARL", "9512458895", "38 Avenue John F. Kennedy, L-1855 Luksemburg"),
    ("Allegro.eu SA", "7792369887", "ul. Grunwaldzka 182, 60-166 Poznań"),
    ("PKN ORLEN SA", "7743211829", "ul. Chemików 7, 09-411 Płock"),
    ("T-Mobile Polska SA", "5261040828", "ul. Marynarska 12, 02-674 Warszawa"),
    ("Orange Polska SA", "5220007034", "Al. Jerozolimskie 160, 02-326 Warszawa"),
    ("Polskie Sieci Elektroenergetyczne SA", "5252271024", "ul. Mysia 2, 00-496 Warszawa"),
    ("Fakturownia Sp. z o.o.", "7010289455", "ul. Juliana Bruna 2, 02-594 Warszawa"),
    ("Santander Leasing SA", "7781436248", "ul. Grochowska 48A, 04-357 Warszawa"),
    ("Poczta Polska SA", "5250007313", "ul. Rodziny Hiszpańskich 8, 00-940 Warszawa"),
    ("PKO Bank Polski SA", "5250026764", "ul. Puławska 15, 02-515 Warszawa"),
    ("DHL Parcel Polska Sp. z o.o.", "5270007345", "ul. Osmańska 2, 02-823 Warszawa"),
]

INVOICE_TYPES = [
    ("Subskrypcja Microsoft 365 Business", Decimal("499.00"), Decimal("114.77"), Decimal("613.77"), False),
    ("Usługi Google Workspace", Decimal("320.00"), Decimal("73.60"), Decimal("393.60"), False),
    ("Serwer VPS OVH", Decimal("89.00"), Decimal("20.47"), Decimal("109.47"), False),
    ("Licencja Adobe Creative Cloud", Decimal("1200.00"), Decimal("276.00"), Decimal("1476.00"), False),
    ("Amazon EC2 — hosting aplikacji", Decimal("2450.00"), Decimal("563.50"), Decimal("3013.50"), True),
    ("Prowizja Allegro — sprzedaż marketplace", Decimal("3200.00"), Decimal("736.00"), Decimal("3936.00"), True),
    ("Paliwo — faktura zbiorcza", Decimal("8500.00"), Decimal("1955.00"), Decimal("10455.00"), True),
    ("Telefonia komórkowa — abonament", Decimal("450.00"), Decimal("103.50"), Decimal("553.50"), False),
    ("Internet światłowodowy — abonament", Decimal("299.00"), Decimal("68.77"), Decimal("367.77"), False),
    ("Energia elektryczna — faktura", Decimal("4200.00"), Decimal("966.00"), Decimal("5166.00"), True),
    ("Opłata za wystawianie faktur elektronicznych", Decimal("99.00"), Decimal("22.77"), Decimal("121.77"), False),
    ("Leasing samochodu dostawczego", Decimal("3800.00"), Decimal("874.00"), Decimal("4674.00"), True),
    ("Usługi pocztowe — przesyłki", Decimal("185.00"), Decimal("42.55"), Decimal("227.55"), False),
    ("Prowizja bankowa — obsługa rachunku", Decimal("120.00"), Decimal("27.60"), Decimal("147.60"), False),
    ("Kurierzy — przesyłki ekspresowe", Decimal("560.00"), Decimal("128.80"), Decimal("688.80"), False),
]

ACCOUNTS = [
    "12102055581111100000000001",
    "50102055581111103350100011",
    "51109010430000000100111111",
    "82600000020260111122223333",
    "06101014690039392223000000",
    "44249000050000000003956399",
    "78113000070001080044222901",
]

STATUSES = [
    Invoice.STATUS_NEW,
    Invoice.STATUS_NEW,
    Invoice.STATUS_NEW,
    Invoice.STATUS_DISPUTED,
    Invoice.STATUS_ACCEPTED,
    Invoice.STATUS_ACCEPTED,
    Invoice.STATUS_SENT_FOR_PAYMENT,
    Invoice.STATUS_PAID,
]


class Command(BaseCommand):
    help = 'Generuje przykładowe faktury kosztowe do testów UI'

    def add_arguments(self, parser):
        parser.add_argument('--count', type=int, default=60)
        parser.add_argument('--clear', action='store_true', help='Usuń istniejące faktury testowe')

    def handle(self, *args, **options):
        if options['clear']:
            deleted = Invoice.objects.filter(ksef_reference_number__startswith='DEMO-').delete()
            self.stdout.write(self.style.WARNING(f'Usunięto {deleted[0]} rekordów.'))

        # Pobierz lub utwórz użytkownika systemowego
        admin = CustomUser.objects.filter(is_superuser=True).first()

        count = options['count']
        today = date.today()
        created = 0

        for i in range(count):
            seller = random.choice(SELLERS)
            inv_type = random.choice(INVOICE_TYPES)
            status = random.choice(STATUSES)

            # Losowa data wystawienia — ostatnie 6 miesięcy
            days_ago = random.randint(1, 180)
            issue_date = today - timedelta(days=days_ago)
            due_date = issue_date + timedelta(days=random.choice([14, 21, 30, 60]))

            # Dla starszych i zaakceptowanych — część przeterminowana
            if status == Invoice.STATUS_ACCEPTED and random.random() < 0.3:
                due_date = today - timedelta(days=random.randint(1, 30))

            ksef_ref = f"DEMO-{issue_date.strftime('%Y%m%d')}-{i:04d}-{random.randint(10000,99999)}"

            # Wariant kwoty (±10%)
            variance = Decimal(str(round(random.uniform(0.9, 1.1), 2)))
            net = round(inv_type[1] * variance, 2)
            vat = round(inv_type[2] * variance, 2)
            gross = net + vat

            invoice = Invoice(
                ksef_reference_number=ksef_ref,
                invoice_number=f"FV/{issue_date.year}/{issue_date.month:02d}/{i+1:04d}",
                seller_name=seller[0],
                seller_nip=seller[1],
                seller_address=seller[2],
                buyer_nip="9512458895",
                amount_net=net,
                amount_vat=vat,
                amount_gross=gross,
                currency="PLN",
                is_split_payment=inv_type[4],
                vat_amount_split=vat if inv_type[4] else None,
                issue_date=issue_date,
                payment_due_date=due_date,
                bank_account_number=random.choice(ACCOUNTS) if random.random() > 0.1 else '',
                payment_title=f'{inv_type[0]} — {ksef_ref}',
                status=status,
                notes="Dane testowe — demo UI." if random.random() < 0.2 else '',
            )
            invoice.save()

            # Dodaj log statusu
            if status != Invoice.STATUS_NEW:
                InvoiceStatusLog.objects.create(
                    invoice=invoice,
                    old_status=Invoice.STATUS_NEW,
                    new_status=status,
                    changed_by=admin,
                    note='Automatycznie wygenerowane — dane demo.',
                    changed_at=timezone.now() - timedelta(days=random.randint(0, days_ago)),
                )

            created += 1

        self.stdout.write(self.style.SUCCESS(
            f'Wygenerowano {created} faktur testowych.'
        ))
        self.stdout.write(f'  Statusy: ' + ', '.join(
            f'{s}={Invoice.objects.filter(status=s, ksef_reference_number__startswith="DEMO-").count()}'
            for s, _ in Invoice.STATUS_CHOICES
        ))
