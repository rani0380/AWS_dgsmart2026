2026 전국기능경기대회 클라우드컴퓨팅 제1과제 배포 파일

파일 구성
1. book
   - Linux AMD64용 Book App 실행 파일
   - 실행 전 chmod +x book 필요
   - 기본 포트: 8080
   - 환경 변수: AWS_REGION, TABLE_NAME

2. index.html
   - S3 정적 웹 콘텐츠
   - main.jpeg와 함께 업로드

3. main.jpeg
   - index.html의 헤더 배경 이미지

Linux 실행 예시
chmod +x book
export AWS_REGION=ap-northeast-2
export TABLE_NAME=unicorn-concert-db
./book

S3 업로드 예시
aws s3 cp index.html s3://unicorn-web-<ACCOUNT_ID>/index.html
aws s3 cp main.jpeg s3://unicorn-web-<ACCOUNT_ID>/main.jpeg
