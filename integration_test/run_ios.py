#!/usr/bin/env python3
"""Run the iOS app against the local Spring API and its development mailbox."""

import argparse
from base64 import b64decode, b64encode
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import os
import re
import secrets
import subprocess
from struct import unpack
from threading import Thread
import time
from urllib.request import urlopen
from urllib.parse import parse_qs, urlencode, urlsplit
from uuid import uuid4


FRONTEND = Path(__file__).resolve().parents[1]
MAILBOX = FRONTEND.parent / 'backend' / '.local-mail'


MAIL_PATTERNS = {
    'signup': r'\d{6}',
    'password-reset': r'finsight-reset://local/password-reset#token=[A-Za-z0-9_-]{43}',
}


def messages(email, kind):
    for message in MAILBOX.glob(f'{kind}-*.txt'):
        try:
            recipient, code = message.read_text().strip().splitlines()
        except (FileNotFoundError, ValueError):
            continue
        if recipient == email and re.fullmatch(MAIL_PATTERNS[kind], code):
            yield message, code


def mailbox_handler(email, route, device, news, notification_database, insight, signup_database, database):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def _read(self, kind):
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                result = next(messages(email, kind), None)
                if result is not None:
                    return result[1]
                time.sleep(.15)
            return None

        def do_GET(self):
            if self.path != route:
                self.send_error(404)
                return
            code = self._read('signup')
            if code is None:
                self.send_error(404, 'Local signup code not found')
                return
            self.send_response(200)
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(code.encode('ascii'))

        def do_POST(self):
            path = urlsplit(self.path)
            if news is not None and path.path in (
                    f'{route}/widget-photo-present', f'{route}/widget-photo-hidden'):
                folder = subprocess.check_output([
                    'xcrun', 'simctl', 'get_app_container', device,
                    'kr.finsight.finsight', 'group.kr.finsight.finsight',
                ], text=True, timeout=5).strip()
                snapshot = json.loads((Path(folder) / 'finsight-home-widget.json').read_text())
                if path.path.endswith('-present'):
                    png = b64decode(snapshot.get('newsImage', ''))
                    valid = (snapshot.get('showContent') is True
                             and snapshot.get('newsId') == str(news.article)
                             and snapshot.get('newsCheckedAt') is not None
                             and png.startswith(b'\x89PNG\r\n\x1a\n')
                             and len(png) >= 24
                             and max(unpack('>II', png[16:24])) <= 288)
                else:
                    valid = (snapshot.get('showContent') is False
                             and all(snapshot.get(key) is None for key in
                                     ('newsImage', 'newsId', 'newsTitle', 'newsCheckedAt')))
                self.send_response(204 if valid else 409)
                self.end_headers()
                return
            if path.path == f'{route}/open-action-widget':
                params = parse_qs(path.query)
                attempt = params.get('attemptId', [''])[0]
                guide = params.get('id', [''])[0]
                if not re.fullmatch(r'[a-fA-F0-9-]{36}', attempt) or not re.fullmatch(r'[a-zA-Z0-9_-]{1,100}', guide):
                    self.send_error(400)
                    return
                revision = sql(database, """
SELECT revision_no FROM published_guide g
WHERE g.content_key=:'guide' AND EXISTS (
  SELECT 1 FROM survey_attempt a JOIN app_user u ON u.id=a.user_id
  WHERE a.id=:'attempt'::uuid AND u.email=:'email'
);
""", capture=True, guide=guide, attempt=attempt, email=email).strip()
                if not revision.isdecimal():
                    self.send_error(404)
                    return
                query = urlencode({
                    'attemptId': attempt,
                    'id': guide,
                    'revision': int(revision) + (params.get('stale') == ['true']),
                })
                self._open_link(f'finsight-widget://open/action?{query}')
                return
            if self.path == f'{route}/expire-signup' and signup_database is not None:
                sql(signup_database, """
UPDATE signup_email_challenge SET sent_at=now()-interval '6 minutes'
WHERE email=:'email' AND used_at IS NULL;
""", email=email)
                for message, _ in messages(email, 'signup'):
                    message.unlink(missing_ok=True)
                self.send_response(204)
                self.end_headers()
                return
            if insight is not None and self.path in (f'{route}/publish-insight', f'{route}/revoke-insight'):
                if self.path.endswith('/publish-insight'):
                    insight.install()
                else:
                    insight.revoke()
                self.send_response(204)
                self.end_headers()
                return
            if self.path == f'{route}/seed-notifications' and notification_database is not None:
                sql(notification_database, """
INSERT INTO app_notification(id,user_id,kind,event_key,title,body,created_at,read_at)
SELECT gen_random_uuid(),u.id,v.kind,v.event_key,v.title,v.body,v.created_at,v.read_at
FROM app_user u CROSS JOIN (VALUES
    ('PERIODIC','e2e-periodic','다시 진단할 시간이에요','요즘 금융 생활을 확인해보세요.',clock_timestamp(),NULL::timestamptz),
    ('ECONOMY','e2e-economy','아침 경제 요약','오늘의 경제 소식을 확인해보세요.',clock_timestamp()-interval '1 day',clock_timestamp())
) AS v(kind,event_key,title,body,created_at,read_at)
WHERE u.email=:'email'
ON CONFLICT (user_id,kind,event_key) DO NOTHING;
""", email=email)
                self.send_response(204)
                self.end_headers()
                return
            if self.path == f'{route}/expire-news' and news is not None:
                news.expire()
                self.send_response(204)
                self.end_headers()
                return
            if self.path != f'{route}/open-reset':
                self.send_error(404)
                return
            link = self._read('password-reset')
            if link is None:
                self.send_error(404, 'Local iOS reset link not found')
                return
            self._open_link(link)

        def _open_link(self, link):
            opened = subprocess.run(['xcrun', 'simctl', 'openurl', device, link],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            self.send_response(204 if opened.returncode == 0 else 500)
            self.end_headers()

    return Handler


def sql(database, statement, *, capture=False, **variables):
    result = subprocess.run(
        ['docker', 'exec', '-i', 'finsight-local-db-1', 'psql', '-X', '-q',
         '-U', 'finsight', '-d', database, '-v', 'ON_ERROR_STOP=1',
         *(['-At'] if capture else []),
         *[argument for key, value in variables.items()
           for argument in ('-v', f'{key}={value}')]],
        input=statement, text=True, check=True, capture_output=capture,
    )
    return result.stdout


class PublishedNews:
    def __init__(self, database):
        self.database = database
        self.editor = uuid4()
        self.article = uuid4()
        self.media = uuid4()

    def _sql(self, statement, **variables):
        sql(self.database, statement, editor=self.editor, article=self.article, media=self.media, **variables)

    def install(self):
        image = (FRONTEND / 'integration_test/fixtures/news-figma.png').read_bytes()
        width = int.from_bytes(image[16:20], 'big')
        height = int.from_bytes(image[20:24], 'big')
        self._sql("""
BEGIN;
INSERT INTO admin_account(id,email,name,password_hash,totp_secret_encrypted,status)
VALUES (:'editor', :'editor' || '@example.test', '검증 편집자', 'fixture', decode('00','hex'), 'ACTIVE');
INSERT INTO media_asset(id,owner_id,mime,width,height,status,bytes)
VALUES (:'media', :'editor', 'image/png', :'width'::int, :'height'::int, 'READY', decode(:'image','base64'));
INSERT INTO news_article(id,source_url)
VALUES (:'article', 'https://www.hankyung.com/article/' || :'article');
INSERT INTO news_revision(article_id,revision,author_id,status,title,summary,body,
                          reason,action,article_published_at,types,starts_at,media_id)
VALUES (:'article',1,:'editor','PUBLISHED',
        '은행 대출금리 4.40% 한 달 새 0.13%p 올랐어요',
        '은행이 새로 취급한 대출의 평균금리가 4.27%에서 4.40%로 상승했어요.',
        '가계대출 금리 4.76%\n주택담보대출 금리 4.06%\n신규 대출 기준이며 실제 적용 금리는 다를 수 있어요.',
        '내 대출의 금리 방식과 다음 상환 일정을 확인하는 것이 중요해요.',
        '대출 약정에서 금리 방식 확인하기',
        now()-interval '1 hour', ARRAY['DEBT','INCOME','EMERGENCY_FUND','FIXED_COST','FUTURE','FAMILY'],
        now()-interval '1 hour', :'media');
UPDATE news_article SET published_revision=1 WHERE id=:'article';
INSERT INTO news_edition_item(edition_date,type,slot,article_id,article_revision)
SELECT (now() AT TIME ZONE 'Asia/Seoul')::date, item.type, 1, :'article', 1
FROM news_revision r CROSS JOIN unnest(r.types) AS item(type)
WHERE r.article_id=:'article' AND r.revision=1;
COMMIT;
""", image=b64encode(image).decode('ascii'), width=width, height=height)

    def expire(self):
        self._sql("""
UPDATE news_revision SET ends_at=now() WHERE article_id=:'article' AND revision=1;
""")

    def cleanup(self):
        self._sql("""
BEGIN;
DELETE FROM news_edition_item WHERE article_id=:'article';
UPDATE news_article SET published_revision=NULL WHERE id=:'article';
DELETE FROM news_revision WHERE article_id=:'article';
DELETE FROM news_article WHERE id=:'article';
DELETE FROM media_asset WHERE id=:'media';
DELETE FROM admin_account WHERE id=:'editor';
COMMIT;
""")


class PublishedInsight:
    def __init__(self, database):
        self.database = database
        self.ids = {name: uuid4() for name in ('editor', 'snapshot', 'publication', 'content', 'revision')}

    def _sql(self, statement):
        sql(self.database, statement, **self.ids)

    def install(self):
        self._sql("""
BEGIN;
INSERT INTO admin_account(id,email,name,password_hash,totp_secret_encrypted,status)
VALUES (:'editor', :'editor' || '@example.test', '검증 인사이트 편집자', 'fixture', decode('00','hex'), 'ACTIVE');
INSERT INTO comparison_snapshot(id,type,period_start,period_end,formula_version,dataset_version,sample_n,
                                metrics,status,approved_metrics,approval_reason)
SELECT :'snapshot','DEBT',current_date-29,current_date,'yfsi-v1',version,greatest(min_sample,30),
    jsonb_build_object('EXTERNAL_AREA_MEAN', jsonb_build_object(
        'DEBT', jsonb_build_object('mean',60,'n',greatest(min_sample,30)),
        'INCOME', jsonb_build_object('mean',39,'n',greatest(min_sample,30)-1))),
    'APPROVED',ARRAY['EXTERNAL_AREA_MEAN'],CASE WHEN min_sample IS NULL THEN 'ios-e2e-temporary-minimum' END
FROM comparison_dataset WHERE type='DEBT';
UPDATE comparison_dataset SET min_sample=30 WHERE type='DEBT' AND min_sample IS NULL;
INSERT INTO comparison_publication(id,type,snapshot_id,allowed_metrics,starts_at,ends_at,status,approver_id)
VALUES (:'publication','DEBT',:'snapshot',ARRAY['EXTERNAL_AREA_MEAN'],
        now()-interval '1 minute',now()+interval '1 day','ACTIVE',:'editor');
INSERT INTO service_notice(id,kind) VALUES (:'content','INSIGHT');
INSERT INTO service_notice_revision(id,notice_id,revision_no,author_id,status,title,summary,body,
    sort_order,starts_at,types,snapshot_id,metric_key,insight_explanation)
VALUES (:'revision',:'content',1,:'editor','PUBLISHED','한 달 생활비부터 적어보기',
    '필수지출을 나눠 이번 달 부담을 살펴보세요.',
    '한 달 동안 꼭 필요한 생활비를 먼저 적고 조정할 수 있는 지출을 구분해 보세요.',
    0,now()-interval '1 minute',ARRAY['DEBT'],:'snapshot','EXTERNAL_AREA_MEAN','승인된 집계의 부채 영역만 표시합니다.');
UPDATE service_notice SET published_revision_id=:'revision' WHERE id=:'content';
COMMIT;
""")

    def revoke(self):
        self._sql("""
UPDATE comparison_publication SET status='UNPUBLISHED' WHERE id=:'publication' AND status='ACTIVE';
""")

    def cleanup(self):
        self._sql("""
BEGIN;
DELETE FROM app_event WHERE content_kind='INSIGHT' AND content_id=:'content';
UPDATE service_notice SET published_revision_id=NULL WHERE id=:'content';
DELETE FROM insight_helpful WHERE content_id=:'content';
DELETE FROM service_notice WHERE id=:'content';
DELETE FROM comparison_publication WHERE id=:'publication';
UPDATE comparison_dataset SET min_sample=NULL WHERE type='DEBT' AND min_sample=30
    AND EXISTS (SELECT 1 FROM comparison_snapshot WHERE id=:'snapshot' AND approval_reason='ios-e2e-temporary-minimum');
DELETE FROM comparison_snapshot WHERE id=:'snapshot';
DELETE FROM admin_account WHERE id=:'editor';
COMMIT;
""")


def cleanup(email, database):
    for kind in MAIL_PATTERNS:
        for message in MAILBOX.glob(f'{kind}-*.txt'):
            try:
                recipient = message.read_text().split('\n', 1)[0]
            except FileNotFoundError:
                continue
            if recipient == email:
                message.unlink(missing_ok=True)
    sql(database, """
BEGIN;
WITH fixture AS (SELECT id FROM app_user WHERE email = :'email'),
     event_ids AS (SELECT id FROM fixture UNION
        SELECT d.id FROM diagnosis d JOIN survey_attempt a ON a.id=d.attempt_id
        JOIN fixture f ON f.id=a.user_id)
DELETE FROM discord_outbox WHERE state='PENDING' AND event_id IN (SELECT id FROM event_ids);
DELETE FROM app_user WHERE email=:'email';
DELETE FROM signup_email_challenge WHERE email=:'email';
DELETE FROM signup_email_delivery WHERE email=:'email';
COMMIT;
""", email=email)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--api-port', type=int, default=8080)
    isolated_databases = ('finsight_ios_e2e', 'finsight_ios_e2e_repeat')
    parser.add_argument('--database', choices=('finsight', *isolated_databases), default='finsight')
    parser.add_argument('--published-news', action='store_true')
    parser.add_argument('--notifications', action='store_true')
    parser.add_argument('--published-insight', action='store_true')
    parser.add_argument('--expired-signup', action='store_true')
    args = parser.parse_args()
    if (args.published_news or args.notifications or args.published_insight or args.expired_signup) and args.database not in isolated_databases:
        parser.error('News, notifications and insight fixtures require an isolated iOS E2E database')
    if (args.api_port == 8080) != (args.database == 'finsight') or not 1 <= args.api_port <= 65535:
        parser.error('Use port 8080 for finsight and a dedicated port for an isolated iOS E2E database')
    api = f'http://127.0.0.1:{args.api_port}'
    inventory = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json']))
    simulators = [device for runtime, devices in inventory['devices'].items()
                  if '.iOS-' in runtime for device in devices if device['state'] == 'Booted']
    if args.device not in {device['udid'] for device in simulators}:
        parser.error('--device must be the UUID of a booted iOS simulator')
    with urlopen(f'{api}/actuator/health', timeout=5) as response:
        if response.status != 200:
            raise RuntimeError('The local Spring API is unavailable')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        parser.error('--output must be empty so screenshots belong to a single run')
    email = f'ios-e2e-{secrets.token_hex(6)}@example.test'
    route = f'/signup/{secrets.token_urlsafe(24)}'
    news = PublishedNews(args.database) if args.published_news else None
    insight = PublishedInsight(args.database) if args.published_insight else None
    if news is not None:
        news.install()
    try:
        handler = mailbox_handler(email, route, args.device, news,
                                  args.database if args.notifications else None, insight,
                                  args.database if args.expired_signup else None, args.database)
        with ThreadingHTTPServer(('127.0.0.1', 0), handler) as server:
            worker = Thread(target=server.serve_forever, daemon=True)
            worker.start()
            try:
                return subprocess.run(
                    ['flutter', 'drive', '--debug', '--no-dds', '-d', args.device,
                     '--driver=test_driver/ios_e2e.dart', '--target=integration_test/ios_e2e_test.dart',
                     f'--dart-define=FINSIGHT_API_URL={api}',
                     f'--dart-define=FINSIGHT_E2E_EMAIL={email}',
                     f'--dart-define=FINSIGHT_E2E_PUBLISHED_NEWS={str(args.published_news).lower()}',
                     f'--dart-define=FINSIGHT_E2E_NOTIFICATIONS={str(args.notifications).lower()}',
                     f'--dart-define=FINSIGHT_E2E_PUBLISHED_INSIGHT={str(args.published_insight).lower()}',
                     f'--dart-define=FINSIGHT_E2E_EXPIRED_SIGNUP={str(args.expired_signup).lower()}',
                     f'--dart-define=FINSIGHT_E2E_MAILBOX=http://127.0.0.1:{server.server_port}{route}'],
                    cwd=FRONTEND,
                    env={**os.environ, 'FINSIGHT_E2E_SCREENSHOTS': str(output)},
                ).returncode
            finally:
                server.shutdown()
                cleanup(email, args.database)
    finally:
        if insight is not None:
            insight.cleanup()
        if news is not None:
            news.cleanup()


if __name__ == '__main__':
    raise SystemExit(main())
